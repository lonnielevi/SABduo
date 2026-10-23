import Foundation
import Observation
import SwiftUI

/// Screens on the search navigation stack.
enum SearchRoute: Hashable {
    /// Subcategory list for a top-level category.
    case category(IndexerCategory)
    /// Latest releases in a category (nil = everything), searchable within it.
    case browse(IndexerCategory?)
    case release(SearchResult)
    case indexerInfo(Indexer.ID)
}

enum CapsState {
    case loading
    case loaded(IndexerCaps)
    case failed(String)
}

/// Search navigation and per-category results. Owned by `AppStore` so both survive
/// the layout swap on fold/unfold.
@Observable
final class SearchModel {
    private(set) var indexerID: Indexer.ID?
    var path: [SearchRoute] = []
    private(set) var caps: [Indexer.ID: CapsState] = [:]
    /// Latest usage the indexer reported, from caps or a results page.
    private(set) var apiLimits: [Indexer.ID: APILimits] = [:]
    private(set) var sentIDs: Set<SearchResult.ID> = []
    /// Shared across indexers: Newznab category IDs are largely standard.
    private(set) var favorites: [SavedSearch] = SearchModel.loadFavorites()

    /// Created lazily while views render, so not observed; `indexerID` changes cover invalidation.
    @ObservationIgnored private var feeds: [FeedKey: ResultFeed] = [:]

    private enum FeedKey: Hashable {
        /// The search field on the home screen (all categories).
        case home
        case category(Int?)
    }

    /// Feed behind the home screen's search field.
    var homeFeed: ResultFeed { feed(.home, category: nil) }

    func feed(for category: IndexerCategory?) -> ResultFeed {
        feed(.category(category?.id), category: category)
    }

    private func feed(_ key: FeedKey, category: IndexerCategory?) -> ResultFeed {
        if let feed = feeds[key] { return feed }
        let indexerID = indexerID
        let feed = ResultFeed(category: category) { [weak self] limits in
            guard let self, let indexerID else { return }
            apiLimits[indexerID] = limits
        }
        feeds[key] = feed
        return feed
    }

    /// Switches indexer; results and navigation belong to the old one.
    func selectIndexer(_ id: Indexer.ID?) {
        guard id != indexerID else { return }
        feeds.values.forEach { $0.cancel() }
        feeds = [:]
        path = []
        indexerID = id
    }

    /// After an indexer's settings change, drop what was fetched with the old ones.
    func invalidate(_ id: Indexer.ID) {
        caps[id] = nil
        apiLimits[id] = nil
        if id == indexerID {
            feeds.values.forEach { $0.cancel() }
            feeds = [:]
            path = []
        }
    }

    // MARK: Caps

    func loadCaps(for indexer: Indexer, client: NewznabClient?, force: Bool = false) async {
        switch caps[indexer.id] {
        case .loading: return
        case .loaded where !force: return
        default: break
        }
        guard let client else {
            caps[indexer.id] = .failed("Add an API key for \(indexer.name) in Settings.")
            return
        }
        caps[indexer.id] = .loading
        do {
            let loaded = try await client.caps()
            caps[indexer.id] = .loaded(loaded)
            if let limits = loaded.apiLimits { apiLimits[indexer.id] = limits }
        } catch {
            caps[indexer.id] = .failed(error.localizedDescription)
        }
    }

    func loadedCaps(for id: Indexer.ID?) -> IndexerCaps? {
        guard let id, case .loaded(let caps) = caps[id] else { return nil }
        return caps
    }

    /// The indexer's own category tree, or the standard Newznab top level if caps aren't available.
    func categories(for id: Indexer.ID?) -> [IndexerCategory] {
        guard let categories = loadedCaps(for: id)?.categories, !categories.isEmpty else { return IndexerCategory.standard }
        return categories
    }

    func markSent(_ id: SearchResult.ID) {
        sentIDs.insert(id)
    }

    /// Where the indexer serves pages and covers: caps' `url`, else the API URL minus "/api".
    func siteURL(for indexer: Indexer?) -> URL? {
        guard let indexer else { return nil }
        return loadedCaps(for: indexer.id)?.siteURL ?? indexer.apiURL?.deletingLastPathComponent()
    }

    // MARK: Favorites

    private static let favoritesKey = "savedSearches"

    func favorite(query: String, category: IndexerCategory?) -> SavedSearch? {
        favorites.first { $0.matches(query: query, category: category) }
    }

    func toggleFavorite(query: String, category: IndexerCategory?) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        if let existing = favorite(query: query, category: category) {
            favorites.removeAll { $0.id == existing.id }
        } else {
            // Store the category without its subcategories; only id, name and path matter here.
            var stored = category
            stored?.subcategories = []
            favorites.append(SavedSearch(query: query, category: stored))
        }
        saveFavorites()
    }

    func removeFavorites(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        saveFavorites()
    }

    func removeFavorite(_ saved: SavedSearch) {
        favorites.removeAll { $0.id == saved.id }
        saveFavorites()
    }

    func moveFavorites(fromOffsets source: IndexSet, toOffset destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        saveFavorites()
    }

    /// Runs a favorite: across everything on the home screen, or inside its category.
    func run(_ saved: SavedSearch, using client: NewznabClient?) {
        let target = saved.category.map { feed(for: $0) } ?? homeFeed
        target.query = saved.query
        target.load(using: client)
        path = saved.category.map { [.browse($0)] } ?? []
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: Self.favoritesKey)
        }
    }

    private static func loadFavorites() -> [SavedSearch] {
        guard let data = UserDefaults.standard.data(forKey: favoritesKey),
              let saved = try? JSONDecoder().decode([SavedSearch].self, from: data)
        else { return [] }
        return saved
    }
}

/// One list of results: the latest in a category, or a search within it.
@Observable
final class ResultFeed {
    let category: IndexerCategory?
    var query = ""

    private(set) var results: [SearchResult] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    /// Query the current results answer: nil before any load, "" for the latest releases.
    private(set) var loadedQuery: String?

    @ObservationIgnored private var total: Int?
    @ObservationIgnored private var lastPageCount = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let onLimits: (APILimits) -> Void

    init(category: IndexerCategory?, onLimits: @escaping (APILimits) -> Void) {
        self.category = category
        self.onLimits = onLimits
    }

    var hasLoaded: Bool { loadedQuery != nil }

    var canLoadMore: Bool {
        guard hasLoaded, !isLoading, errorMessage == nil else { return false }
        if let total { return results.count < total }
        return lastPageCount >= NewznabClient.pageSize
    }

    private var categoryIDs: [Int] { category.map { [$0.id] } ?? [] }

    /// Loads page one for the current query (empty = latest). Indexers rate-limit API hits,
    /// so callers only invoke this on submit, on first appearance, or on pull-to-refresh.
    @discardableResult
    func load(using client: NewznabClient?) -> Task<Void, Never>? {
        guard let client else { return nil }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        task?.cancel()
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        task = Task {
            do {
                let page = try await client.search(query, categoryIDs: categoryIDs)
                guard !Task.isCancelled else { return }
                results = page.results
                total = page.total
                lastPageCount = page.results.count
                if let limits = page.apiLimits { onLimits(limits) }
            } catch {
                guard !Task.isCancelled, !Self.isCancellation(error) else { return }
                results = []
                errorMessage = error.localizedDescription
            }
            loadedQuery = query
            isLoading = false
        }
        return task
    }

    func loadMore(using client: NewznabClient?) {
        guard let client, let loadedQuery, canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        let offset = results.count
        task = Task {
            defer { isLoadingMore = false }
            do {
                let page = try await client.search(loadedQuery, categoryIDs: categoryIDs, offset: offset)
                let known = Set(results.map(\.id))
                results += page.results.filter { !known.contains($0.id) }
                total = page.total ?? total
                lastPageCount = page.results.count
                if let limits = page.apiLimits { onLimits(limits) }
            } catch {
                guard !Self.isCancellation(error) else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Back to "nothing loaded" (e.g. the home search field was cleared).
    func clear() {
        cancel()
        results = []
        loadedQuery = nil
        errorMessage = nil
    }

    func cancel() {
        task?.cancel()
        isLoading = false
        isLoadingMore = false
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
