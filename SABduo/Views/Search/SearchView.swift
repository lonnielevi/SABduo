import SwiftUI

/// Search home: the active indexer, its category tree, and a search across everything.
struct SearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.rootActions) private var actions

    var body: some View {
        let indexer = store.activeIndexer
        let client = store.newznabClient(for: indexer)
        @Bindable var feed = store.search.homeFeed

        List {
            if feed.hasLoaded || feed.isLoading {
                ResultsList(feed: feed, client: client)
            } else if let indexer, client != nil {
                Section {
                    NavigationLink(value: SearchRoute.indexerInfo(indexer.id)) {
                        IndexerSummaryRow(indexer: indexer)
                    }
                }

                Section {
                    NavigationLink(value: SearchRoute.browse(nil)) {
                        Label("Latest Releases", systemImage: "clock.arrow.circlepath")
                    }
                }

                if !store.search.favorites.isEmpty {
                    Section {
                        ForEach(store.search.favorites) { saved in
                            Button { store.search.run(saved, using: client) } label: {
                                FavoriteRow(saved: saved)
                            }
                            .foregroundStyle(.primary)
                            .contextMenu {
                                Button("Remove from Favorites", systemImage: "star.slash", role: .destructive) {
                                    store.search.removeFavorite(saved)
                                }
                            }
                        }
                        .onDelete { store.search.removeFavorites(at: $0) }
                        .onMove { store.search.moveFavorites(fromOffsets: $0, toOffset: $1) }
                    } header: {
                        Text("Favorites")
                    }
                }

                Section {
                    ForEach(store.search.categories(for: indexer.id)) { category in
                        NavigationLink(value: category.subcategories.isEmpty ? SearchRoute.browse(category) : .category(category)) {
                            CategoryRow(category: category)
                        }
                    }
                } header: {
                    Text("Categories")
                } footer: {
                    switch store.search.caps[indexer.id] {
                    case .loading:
                        Text("Loading \(indexer.name)'s categories…")
                    case .failed(let message):
                        Text("Couldn't load \(indexer.name)'s categories (\(message)). Showing the standard ones.")
                    default:
                        EmptyView()
                    }
                }
            }
        }
        .overlay {
            if indexer == nil || client == nil {
                ContentUnavailableView {
                    Label("No Indexer", systemImage: "magnifyingglass")
                } description: {
                    Text("Add a Newznab indexer such as NZB.life with its API key.")
                } actions: {
                    Button("Add Indexer", action: actions.showSettings)
                }
            } else if feed.hasLoaded || feed.isLoading {
                FeedStatus(feed: feed, name: indexer?.name ?? "the indexer")
            }
        }
        .searchable(text: $feed.query, prompt: indexer.map { "Search \($0.name)" } ?? "Search")
        .searchSuggestions {
            FavoriteSuggestions(typed: feed.query) { store.search.run($0, using: client) }
        }
        .onSubmit(of: .search) { feed.load(using: client) }
        .onChange(of: feed.query) {
            // Clearing the field returns to the category list.
            if feed.query.isEmpty { feed.clear() }
        }
        .refreshable {
            if feed.hasLoaded {
                await feed.load(using: client)?.value
            } else if let indexer {
                await store.search.loadCaps(for: indexer, client: client, force: true)
            }
        }
        .task(id: indexer?.id) {
            guard let indexer else { return }
            await store.search.loadCaps(for: indexer, client: client)
        }
        .navigationTitle("Search")
        .toolbar {
            if let query = feed.loadedQuery, !query.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { FavoriteButton(query: query, category: nil) }
            }
            ToolbarItem(placement: .topBarTrailing) { IndexerMenu() }
        }
    }
}

private struct IndexerSummaryRow: View {
    @Environment(AppStore.self) private var store
    let indexer: Indexer

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(indexer.name).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts = [indexer.apiURL?.host() ?? indexer.address]
        if let limits = store.search.apiLimits[indexer.id], let current = limits.apiCurrent, let max = limits.apiMax {
            parts.append("\(current)/\(max) API hits")
        }
        return parts.joined(separator: " · ")
    }
}

struct CategoryRow: View {
    let category: IndexerCategory

    var body: some View {
        LabeledContent {
            if !category.subcategories.isEmpty {
                Text("\(category.subcategories.count)")
            }
        } label: {
            Label {
                Text(category.name)
                if let detail = category.detail, detail != category.name {
                    Text(detail)
                }
            } icon: {
                Image(systemName: category.systemImage)
            }
        }
    }
}
