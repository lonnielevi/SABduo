import SwiftUI

/// A top-level category's subcategories.
struct CategoryView: View {
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
        .navigationTitle(category.name)
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
                    Text("Results for “\(query)”")
                }
            } else {
                ResultsList(feed: feed, client: client)
            }
        }
        .overlay { FeedStatus(feed: feed, name: name) }
        .searchable(text: $feed.query, prompt: "Search \(name)")
        .searchSuggestions {
            FavoriteSuggestions(typed: feed.query, category: category) { saved in
                feed.query = saved.query
                feed.load(using: client)
            }
        }
        .onSubmit(of: .search) { feed.load(using: client) }
        .onChange(of: feed.query) {
            // Clearing a search goes back to the latest releases in this category.
            if feed.query.isEmpty, feed.loadedQuery?.isEmpty == false { feed.load(using: client) }
        }
        .refreshable { await feed.load(using: client)?.value }
        .task {
            if !feed.hasLoaded, !feed.isLoading { feed.load(using: client) }
        }
        .toolbar {
            if let query = feed.loadedQuery, !query.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { FavoriteButton(query: query, category: category) }
            }
        }
        .navigationTitle(category?.name ?? "Latest Releases")
        .navigationSubtitle(category?.parentName ?? indexer?.name ?? "")
    }
}
