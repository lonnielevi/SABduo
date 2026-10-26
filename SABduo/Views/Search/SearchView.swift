import SwiftUI

/// Search home: the active indexer, its category tree, and a search across everything.
struct SearchView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.rootActions) private var actions
    /// Arranging the home screen: every favorite and category shows, with a handle to move it and
    /// an eye to hide or show it.
    @State private var editing = false

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

                if !store.search.favorites.isEmpty {
                    let favorites = store.search.favorites.filter { editing || !store.search.hiddenFavoriteIDs.contains($0.id) }
                    Section {
                        ForEach(favorites) { saved in
                            if editing {
                                let hidden = store.search.hiddenFavoriteIDs.contains(saved.id)
                                VisibilityRow(hidden: hidden) {
                                    store.search.setFavorite(saved, hidden: !hidden)
                                } label: {
                                    FavoriteRow(saved: saved)
                                }
                            } else {
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
                        }
                        .onDelete { offsets in
                            for saved in offsets.map({ favorites[$0] }) { store.search.removeFavorite(saved) }
                        }
                        // Editing shows every favorite, so offsets match the stored order.
                        .onMove(perform: editing ? { store.search.moveFavorites(fromOffsets: $0, toOffset: $1) } : nil)
                        // While editing, the eye hides a favorite; deleting stays a swipe away outside it.
                        .deleteDisabled(editing)
                    } header: {
                        EditableHeader(title: "Favorites", editing: $editing)
                    }
                }

                let allCategories = store.search.categories(for: indexer.id)
                let categories = allCategories.filter { editing || !store.search.hiddenCategoryIDs.contains($0.id) }
                Section {
                    ForEach(categories) { category in
                        if editing {
                            let hidden = store.search.hiddenCategoryIDs.contains(category.id)
                            VisibilityRow(hidden: hidden) {
                                store.search.setCategory(category, hidden: !hidden)
                            } label: {
                                CategoryRow(category: category)
                            }
                        } else {
                            NavigationLink(value: category.subcategories.isEmpty ? SearchRoute.browse(category) : .category(category)) {
                                CategoryRow(category: category)
                            }
                        }
                    }
                    .onMove(perform: editing ? { store.search.moveCategories(allCategories, fromOffsets: $0, toOffset: $1) } : nil)
                } header: {
                    EditableHeader(title: "Categories", editing: $editing)
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
        .environment(\.editMode, .constant(editing ? .active : .inactive))
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

/// A section header with the Edit button that arranges the home screen. Each section has one, so
/// it's in reach whichever is in view; they share one editing state.
private struct EditableHeader: View {
    let title: String
    @Binding var editing: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(editing ? "Done" : "Edit") {
                withAnimation { editing.toggle() }
            }
            .font(.subheadline.weight(editing ? .semibold : .regular))
            .textCase(nil)
        }
    }
}

/// A row while arranging the home screen: dimmed when hidden, with an eye that shows which.
/// Tapping it hides or shows it.
private struct VisibilityRow<Label: View>: View {
    let hidden: Bool
    let toggle: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button {
            withAnimation(.snappy) { toggle() }
        } label: {
            HStack {
                label
                    .opacity(hidden ? 0.4 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: hidden ? "eye.slash" : "eye")
                    .foregroundStyle(hidden ? Color.secondary : Color.accentColor)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 28)
            }
            .contentShape(.rect)
        }
        // Plain, so the row keeps its icon colours rather than taking the button's tint.
        .buttonStyle(.plain)
        .accessibilityValue(hidden ? "Hidden" : "Shown")
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
