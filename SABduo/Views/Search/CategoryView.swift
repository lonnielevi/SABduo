import SwiftUI

/// A top-level category's subcategories.
struct CategoryView: View {
    @Environment(AppStore.self) private var store
    let category: IndexerCategory

    var body: some View {
        List {
            Section {
                NavigationLink(value: SearchRoute.browse(category)) {
                    Label("All \(category.name)", systemImage: category.systemImage)
                }
            }
            Section("Subcategories") {
                ForEach(category.subcategories) { subcategory in
                    NavigationLink(value: SearchRoute.browse(subcategory)) {
                        CategoryRow(category: subcategory)
                    }
                }
            }
        }
        .searchScreenTitle(category.name, subtitle: store.activeIndexer?.name ?? "")
    }
}

/// Latest releases in a category, with a search field scoped to it.
struct BrowseView: View {
    @Environment(AppStore.self) private var store
    let category: IndexerCategory?

    var body: some View {
        let indexer = store.activeIndexer
        let client = store.newznabClient(for: indexer)
        @Bindable var feed = store.search.feed(for: category)
        let name = category?.path ?? "All Categories"

        List {
            if let query = feed.loadedQuery, !query.isEmpty, !feed.results.isEmpty {
                Section {
                    ResultsList(feed: feed, client: client)
                } header: {
                    ResultsHeader(query: query, category: category)
                }
            } else {
                ResultsList(feed: feed, client: client)
            }
        }
        .overlay { FeedStatus(feed: feed, name: name) }
        .onChange(of: feed.query) {
            // Clearing a search goes back to the latest releases in this category.
            if feed.query.isEmpty, feed.loadedQuery?.isEmpty == false { feed.load(using: client) }
        }
        .refreshable { await feed.load(using: client)?.value }
        .task {
            if !feed.hasLoaded, !feed.isLoading { feed.load(using: client) }
        }
        .searchScreenTitle(category?.name ?? "Latest Releases", subtitle: category?.parentName ?? indexer?.name ?? "")
    }
}
