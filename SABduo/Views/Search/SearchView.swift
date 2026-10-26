import SwiftUI

/// Search home: the active indexer, its category tree, and a search across everything.
struct SearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.rootActions) private var actions
    /// Whether hidden favorites and categories show, dimmed, so a swipe can show them again.
    @State private var showHidden = false

    var body: some View {
        let indexer = store.activeIndexer
        let client = store.newznabClient(for: indexer)
        @Bindable var feed = store.search.homeFeed

        List {
            if let query = feed.loadedQuery, !query.isEmpty, !feed.results.isEmpty {
                Section {
                    ResultsList(feed: feed, client: client)
                } header: {
                    ResultsHeader(query: query, category: nil)
                }
            } else if feed.hasLoaded || feed.isLoading {
                ResultsList(feed: feed, client: client)
            } else if let indexer, client != nil {
                Section {
                    IndexerPicker(indexer: indexer)
                }

                // A section goes, header and all, when everything in it is hidden.
                let favorites = store.search.favorites.filter { showHidden || !store.search.hiddenFavoriteIDs.contains($0.id) }
                if !favorites.isEmpty {
                    Section {
                        ForEach(favorites) { saved in
                            let hidden = store.search.hiddenFavoriteIDs.contains(saved.id)
                            Button { store.search.run(saved, using: client) } label: {
                                FavoriteRow(saved: saved).opacity(hidden ? 0.4 : 1)
                            }
                            .foregroundStyle(.primary)
                            .contextMenu {
                                Button("Remove from Favorites", systemImage: "heart.slash", role: .destructive) {
                                    store.search.removeFavorite(saved)
                                }
                            }
                            // A swipe only offers hiding or deleting; either takes a tap.
                            .swipeActions(allowsFullSwipe: false) {
                                HideButton(hidden: hidden) { store.search.setFavorite(saved, hidden: !hidden) }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    withAnimation { store.search.removeFavorite(saved) }
                                }
                            }
                        }
                        .onMove { store.search.moveFavorites(favorites, fromOffsets: $0, toOffset: $1) }
                    } header: {
                        Text("Favorites")
                    }
                }

                let allCategories = store.search.categories(for: indexer.id)
                let categories = allCategories.filter { showHidden || !store.search.hiddenCategoryIDs.contains($0.id) }
                if !categories.isEmpty {
                    Section {
                        ForEach(categories) { category in
                            let hidden = store.search.hiddenCategoryIDs.contains(category.id)
                            NavigationLink(value: category.subcategories.isEmpty ? SearchRoute.browse(category) : .category(category)) {
                                CategoryRow(category: category).opacity(hidden ? 0.4 : 1)
                            }
                            // Categories come from the indexer, so they hide rather than delete. As with
                            // favorites, a swipe only offers it.
                            .swipeActions(allowsFullSwipe: false) {
                                HideButton(hidden: hidden) { store.search.setCategory(category, hidden: !hidden) }
                            }
                        }
                        .onMove { store.search.moveCategories(categories, among: allCategories, fromOffsets: $0, toOffset: $1) }
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

                let anyHidden = store.search.favorites.contains { store.search.hiddenFavoriteIDs.contains($0.id) }
                    || allCategories.contains { store.search.hiddenCategoryIDs.contains($0.id) }
                if anyHidden || showHidden {
                    Section {
                        Button(showHidden ? "Done" : "Show Hidden") {
                            withAnimation { showHidden.toggle() }
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        // Plain text under the list, like a section's footer, rather than a row.
                        .listRowBackground(Color.clear)
                    }
                    .listSectionSpacing(.compact)
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
        .searchScreenTitle("Search", prominent: true)
    }
}

/// Hides a favorite or category from the home screen, or shows it again while hidden ones show.
private struct HideButton: View {
    let hidden: Bool
    let toggle: () -> Void

    var body: some View {
        Button(hidden ? "Show" : "Hide", systemImage: hidden ? "eye" : "eye.slash") {
            withAnimation(.snappy) { toggle() }
        }
        .tint(.gray)
    }
}

/// Which indexer search uses. Its details and settings are on the Settings page.
private struct IndexerPicker: View {
    @Environment(AppStore.self) private var store
    let indexer: Indexer

    var body: some View {
        Menu {
            Picker("Indexer", selection: Binding(
                get: { store.activeIndexer?.id },
                set: { store.search.selectIndexer($0) }
            )) {
                ForEach(store.indexers) { Text($0.name).tag(Optional($0.id)) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36)
                Text(indexer.name)
                    .font(.headline)
                ConnectionLight(state: store.search.reachable[indexer.id], name: indexer.name)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        // A row like the ones below it, not a tinted button.
        .tint(.primary)
        .accessibilityLabel("Indexer: \(indexer.name)")
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
