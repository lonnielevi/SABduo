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
    var path: [SearchRoute] = [] {
        didSet { resetSearches(enteredFrom: oldValue) }
    }
    /// The search field is open: focused, with the keyboard up.
    var fieldOpen = false
    private(set) var caps: [Indexer.ID: CapsState] = [:]
    /// Whether the indexer answered its latest request, caps or search; missing until one does.
    private(set) var reachable: [Indexer.ID: Bool] = [:]
    /// Latest usage the indexer reported, from caps or a results page.
    private(set) var apiLimits: [Indexer.ID: APILimits] = [:]
    /// Releases already handed to SABnzbd, kept across launches so a resend is a choice, not an accident.
    private(set) var sentIDs: Set<SearchResult.ID> = Set(UserDefaults.standard.stringArray(forKey: SearchModel.sentKey) ?? [])
    /// Shared across indexers: Newznab category IDs are largely standard.
    private(set) var favorites: [SavedSearch] = SearchModel.loadFavorites()
    /// Top-level categories left off the search home screen, and the order the rest go in. Shared
    /// across indexers, like favorites.
    private(set) var hiddenCategoryIDs: Set<Int> = Set(UserDefaults.standard.array(forKey: SearchModel.hiddenCategoriesKey) as? [Int] ?? [])
    private var categoryOrder: [Int] = UserDefaults.standard.array(forKey: SearchModel.categoryOrderKey) as? [Int] ?? []
    /// Favorites left off the search home screen.
    private(set) var hiddenFavoriteIDs: Set<SavedSearch.ID> = Set((UserDefaults.standard.stringArray(forKey: SearchModel.hiddenFavoritesKey) ?? []).compactMap(UUID.init))

    /// Created lazily while views render, so not observed; `indexerID` changes cover invalidation.
    @ObservationIgnored private var capsTasks: [Indexer.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var feeds: [FeedKey: ResultFeed] = [:]

    private enum FeedKey: Hashable {
        /// The search field on the home screen (every category not hidden).
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
            reachable[indexerID] = true
            if let limits { apiLimits[indexerID] = limits }
        } onFailure: { [weak self] in
            guard let self, let indexerID else { return }
            reachable[indexerID] = false
        }
        if key == .home {
            feed.homeCategoryIDs = { [weak self] in self?.searchedCategoryIDs ?? [] }
        }
        feeds[key] = feed
        return feed
    }

    /// What a search from the home screen covers: everything, or only the categories left showing
    /// once some are hidden.
    private var searchedCategoryIDs: [Int] {
        let all = categories(for: indexerID)
        guard all.contains(where: { hiddenCategoryIDs.contains($0.id) }) else { return [] }
        return all.map(\.id).filter { !hiddenCategoryIDs.contains($0) }
    }

    /// The feed a search typed now applies to: the category open here or nearest above (a release
    /// searches the list it came from), or everything.
    var activeFeed: ResultFeed {
        scope.map { feed(for: $0.category) } ?? homeFeed
    }

    /// The category the current screen sits in, and where on the path it was opened.
    private var scope: (index: Int, category: IndexerCategory?)? {
        for (index, route) in path.enumerated().reversed() {
            switch route {
            case .browse(let category): return (index, category)
            case .category(let category): return (index, category)
            case .release: continue
            }
        }
        return nil
    }

    /// Runs a search typed outside a page's own field, showing its results: everything on the home
    /// screen, a category's in its list of releases, opened from its subcategories if need be.
    func submit(_ feed: ResultFeed, using client: NewznabClient?) {
        if feed === homeFeed {
            path = []
        } else if let scope, feed === self.feed(for: scope.category) {
            path.removeSubrange((scope.index + 1)...)
            if case .category(let category) = path.last { path.append(.browse(category)) }
        }
        feed.load(using: client)
    }

    /// A search in a category, typed or a favorite's, lasts while the category is open: going back
    /// into it after backing out starts from the latest releases again. Reset on the way in, not
    /// out, so the list doesn't empty while it slides away.
    private func resetSearches(enteredFrom oldPath: [SearchRoute]) {
        let wasOpen = Set(oldPath.compactMap { Self.feedKey($0) })
        for key in Set(path.compactMap { Self.feedKey($0) }).subtracting(wasOpen) {
            guard let feed = feeds[key], feed.query != "" || feed.loadedQuery?.isEmpty == false else { continue }
            feed.query = ""
            feed.clear()
        }
    }

    private static func feedKey(_ route: SearchRoute) -> FeedKey? {
        switch route {
        case .browse(let category): .category(category?.id)
        case .category(let category): .category(category.id)
        case .release: nil
        }
    }

    /// Back to the categories, from any depth or from home-screen results.
    var isHome: Bool { path.isEmpty && !homeFeed.hasLoaded && !homeFeed.isLoading }

    func goHome() {
        path = []
        homeFeed.query = ""
        homeFeed.clear()
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
        case .loading:
            await capsTasks[indexer.id]?.value
            return
        case .loaded where !force: return
        default: break
        }
        guard let client else {
            caps[indexer.id] = .failed("Add an API key for \(indexer.name) in Settings.")
            reachable[indexer.id] = false
            return
        }
        caps[indexer.id] = .loading
        // A task of its own, so the request outlives the view that asked for it: the search screen
        // restarts its task when the layout rebuilds, and a cancelled load would read as a failure.
        let task = Task {
            do {
                let loaded = try await client.caps()
                caps[indexer.id] = .loaded(loaded)
                reachable[indexer.id] = true
                if let limits = loaded.apiLimits { apiLimits[indexer.id] = limits }
            } catch {
                caps[indexer.id] = .failed(error.localizedDescription)
                reachable[indexer.id] = false
            }
            capsTasks[indexer.id] = nil
        }
        capsTasks[indexer.id] = task
        await task.value
    }

    func loadedCaps(for id: Indexer.ID?) -> IndexerCaps? {
        guard let id, case .loaded(let caps) = caps[id] else { return nil }
        return caps
    }

    /// The indexer's own category tree, or the standard Newznab top level if caps aren't available,
    /// in the order arranged on the home screen. Categories never arranged keep the indexer's order, after the rest.
    func categories(for id: Indexer.ID?) -> [IndexerCategory] {
        let loaded = loadedCaps(for: id)?.categories ?? []
        let categories = loaded.isEmpty ? IndexerCategory.standard : loaded
        let rank = Dictionary(categoryOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return categories.enumerated()
            .sorted { (rank[$0.element.id] ?? categoryOrder.count + $0.offset, $0.offset) < (rank[$1.element.id] ?? categoryOrder.count + $1.offset, $1.offset) }
            .map(\.element)
    }

    /// Moves among the categories on screen; hidden ones off screen keep their places.
    func moveCategories(_ shown: [IndexerCategory], among categories: [IndexerCategory], fromOffsets source: IndexSet, toOffset destination: Int) {
        let ids = Self.moving(shown.map(\.id), within: categories.map(\.id), fromOffsets: source, toOffset: destination)
        // Keep the places of categories this indexer doesn't have, for the next one that does.
        categoryOrder = ids + categoryOrder.filter { !ids.contains($0) }
        UserDefaults.standard.set(categoryOrder, forKey: Self.categoryOrderKey)
    }

    func markSent(_ id: SearchResult.ID) {
        guard sentIDs.insert(id).inserted else { return }
        // Oldest first, capped so the list doesn't grow forever.
        var order = UserDefaults.standard.stringArray(forKey: Self.sentKey) ?? []
        order.append(id)
        order = Array(order.suffix(Self.sentLimit))
        sentIDs = Set(order)
        UserDefaults.standard.set(order, forKey: Self.sentKey)
    }

    /// Where the indexer serves pages and covers: caps' `url`, else the API URL minus "/api".
    func siteURL(for indexer: Indexer?) -> URL? {
        guard let indexer else { return nil }
        return loadedCaps(for: indexer.id)?.siteURL ?? indexer.apiURL?.deletingLastPathComponent()
    }

    func setCategory(_ category: IndexerCategory, hidden: Bool) {
        if hidden {
            hiddenCategoryIDs.insert(category.id)
        } else {
            hiddenCategoryIDs.remove(category.id)
        }
        UserDefaults.standard.set(Array(hiddenCategoryIDs), forKey: Self.hiddenCategoriesKey)
    }

    func setFavorite(_ saved: SavedSearch, hidden: Bool) {
        if hidden {
            hiddenFavoriteIDs.insert(saved.id)
        } else {
            hiddenFavoriteIDs.remove(saved.id)
        }
        UserDefaults.standard.set(hiddenFavoriteIDs.map(\.uuidString), forKey: Self.hiddenFavoritesKey)
    }

    /// Moves within the shown items, then puts them back in the slots they held among all of them.
    private static func moving<ID: Equatable>(_ shown: [ID], within all: [ID], fromOffsets source: IndexSet, toOffset destination: Int) -> [ID] {
        var moved = shown
        moved.move(fromOffsets: source, toOffset: destination)
        var next = moved.makeIterator()
        return all.map { shown.contains($0) ? next.next()! : $0 }
    }

    private static let hiddenCategoriesKey = "hiddenCategoryIDs"
    private static let categoryOrderKey = "categoryOrder"
    private static let hiddenFavoritesKey = "hiddenFavoriteIDs"

    // MARK: Favorites

    private static let favoritesKey = "savedSearches"
    private static let sentKey = "sentReleaseIDs"
    private static let sentLimit = 500

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

    func removeFavorite(_ saved: SavedSearch) {
        favorites.removeAll { $0.id == saved.id }
        saveFavorites()
    }

    /// Moves among the favorites on screen; hidden ones off screen keep their places.
    func moveFavorites(_ shown: [SavedSearch], fromOffsets source: IndexSet, toOffset destination: Int) {
        let order = Self.moving(shown.map(\.id), within: favorites.map(\.id), fromOffsets: source, toOffset: destination)
        let byID = Dictionary(uniqueKeysWithValues: favorites.map { ($0.id, $0) })
        favorites = order.compactMap { byID[$0] }
        saveFavorites()
    }

    /// Runs a favorite: across everything on the home screen, or inside its category.
    func run(_ saved: SavedSearch, using client: NewznabClient?) {
        // The path first: opening the category resets its feed, before the favorite's search.
        path = saved.category.map { [.browse($0)] } ?? []
        let target = saved.category.map { feed(for: $0) } ?? homeFeed
        target.query = saved.query
        target.load(using: client)
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
    /// Each answer from the indexer, with the usage it reported if any.
    @ObservationIgnored private let onReply: (APILimits?) -> Void
    @ObservationIgnored private let onFailure: () -> Void
    /// Without a category, the categories a search covers; empty means all of them.
    @ObservationIgnored var homeCategoryIDs: () -> [Int] = { [] }

    init(category: IndexerCategory?, onReply: @escaping (APILimits?) -> Void, onFailure: @escaping () -> Void) {
        self.category = category
        self.onReply = onReply
        self.onFailure = onFailure
    }

    var hasLoaded: Bool { loadedQuery != nil }

    var canLoadMore: Bool {
        guard hasLoaded, !isLoading, errorMessage == nil else { return false }
        if let total { return results.count < total }
        return lastPageCount >= NewznabClient.pageSize
    }

    private var categoryIDs: [Int] { category.map { [$0.id] } ?? homeCategoryIDs() }

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
                onReply(page.apiLimits)
            } catch {
                guard !Task.isCancelled, !Self.isCancellation(error) else { return }
                results = []
                errorMessage = error.localizedDescription
                onFailure()
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
                onReply(page.apiLimits)
            } catch {
                guard !Self.isCancellation(error) else { return }
                errorMessage = error.localizedDescription
                onFailure()
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
