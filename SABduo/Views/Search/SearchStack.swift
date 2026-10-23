import SwiftUI

/// Navigation for search, shared by the Search tab (folded) and the trailing pane (unfolded).
/// The path lives in `SearchModel`, so the current screen survives a fold/unfold.
struct SearchStack: View {
    @Environment(AppStore.self) private var store
    var showsPanePicker = false

    var body: some View {
        NavigationStack(path: Bindable(store.search).path) {
            SearchView()
                .secondaryPanePicker(showsPanePicker)
                .navigationDestination(for: SearchRoute.self) { route in
                    switch route {
                    case .category(let category): CategoryView(category: category)
                    case .browse(let category): BrowseView(category: category)
                    case .release(let result): ReleaseDetailView(result: result)
                    case .indexerInfo(let id): IndexerInfoView(indexerID: id)
                    }
                }
        }
    }
}

/// Indexer switcher plus shortcuts to its info and settings.
struct IndexerMenu: View {
    @Environment(AppStore.self) private var store
    @Environment(\.rootActions) private var actions

    var body: some View {
        Menu {
            if store.indexers.count > 1 {
                Picker("Indexer", selection: Binding(
                    get: { store.activeIndexer?.id },
                    set: { store.search.selectIndexer($0) }
                )) {
                    ForEach(store.indexers) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            if let indexer = store.activeIndexer {
                Button("About \(indexer.name)", systemImage: "info.circle") {
                    store.search.path.append(.indexerInfo(indexer.id))
                }
            }
            Button("Manage Indexers…", systemImage: "gearshape", action: actions.showSettings)
        } label: {
            Label("Indexer", systemImage: "server.rack")
        }
    }
}
