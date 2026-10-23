import Foundation
import Observation

/// Indexer search state. Owned by `AppStore` so a search survives the layout swap on fold/unfold.
@Observable
final class SearchModel {
    var query = ""
    var category: SearchCategory = .all
    var indexerID: Indexer.ID?
    var errorMessage: String?

    private(set) var results: [SearchResult] = []
    private(set) var isSearching = false
    private(set) var isLoadingMore = false
    /// The query/category the current results belong to, so "Load More" pages the right search.
    private(set) var searched: (query: String, category: SearchCategory)?
    private(set) var sentIDs: Set<SearchResult.ID> = []
    private var total: Int?
    private var lastPageCount = 0
    private var task: Task<Void, Never>?

    var hasSearched: Bool { searched != nil }

    var canLoadMore: Bool {
        guard hasSearched, !isSearching else { return false }
        if let total { return results.count < total }
        return lastPageCount >= NewznabClient.pageSize
    }

    /// Runs a fresh search. Indexers rate-limit API hits, so this is only called on submit.
    func submit(using client: NewznabClient?) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client, !trimmed.isEmpty else { return }
        task?.cancel()
        let category = category
        isSearching = true
        isLoadingMore = false
        errorMessage = nil
        task = Task {
            defer { if !Task.isCancelled { isSearching = false } }
            do {
                let page = try await client.search(trimmed, category: category)
                guard !Task.isCancelled else { return }
                results = page.results
                total = page.total
                lastPageCount = page.results.count
                searched = (trimmed, category)
            } catch {
                guard !Task.isCancelled, !Self.isCancellation(error) else { return }
                results = []
                searched = (trimmed, category)
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadMore(using client: NewznabClient?) {
        guard let client, let searched, canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        let offset = results.count
        task = Task {
            defer { isLoadingMore = false }
            do {
                let page = try await client.search(searched.query, category: searched.category, offset: offset)
                let known = Set(results.map(\.id))
                results += page.results.filter { !known.contains($0.id) }
                total = page.total ?? total
                lastPageCount = page.results.count
            } catch {
                guard !Self.isCancellation(error) else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    func markSent(_ id: SearchResult.ID) {
        sentIDs.insert(id)
    }

    /// Drops results when the indexer changes; they belong to the old one.
    func reset() {
        task?.cancel()
        results = []
        searched = nil
        total = nil
        isSearching = false
        isLoadingMore = false
        errorMessage = nil
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
