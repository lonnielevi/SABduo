import SwiftUI

/// Folded: one column, queue and history as tabs, job detail pushed on the queue stack.
struct CompactLayout: View {
    @Environment(AppStore.self) private var store
    @State private var tab: TabID = .queue

    private enum TabID { case queue, history, search }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Queue", systemImage: "arrow.down.circle", value: TabID.queue) {
                // The path mirrors `selectedJobID`, so a job opened while unfolded stays open after folding.
                NavigationStack(path: selectionPath) {
                    QueueView()
                        .navigationDestination(for: QueueSlot.ID.self) { id in
                            JobDetailView(jobID: id)
                        }
                }
            }
            .badge(store.slots.count)

            Tab("History", systemImage: "clock", value: TabID.history) {
                NavigationStack {
                    HistoryView()
                }
            }

            Tab("Search", systemImage: "magnifyingglass", value: TabID.search, role: .search) {
                SearchStack()
            }
        }
        .onAppear {
            // Carry over what was beside the queue when unfolded; an open job wins.
            if store.selectedJobID != nil {
                tab = .queue
            } else if store.secondaryPane == .search {
                tab = .search
            }
        }
        .onChange(of: tab) {
            switch tab {
            case .history: store.secondaryPane = .history
            case .search: store.secondaryPane = .search
            case .queue: break
            }
        }
    }

    private var selectionPath: Binding<[QueueSlot.ID]> {
        Binding(
            get: { store.selectedJobID.map { [$0] } ?? [] },
            set: { store.selectedJobID = $0.last }
        )
    }
}
