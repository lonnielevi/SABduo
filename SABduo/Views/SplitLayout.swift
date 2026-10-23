import SwiftUI

/// Unfolded: queue on the leading half; the selected job, history or search on the trailing half.
/// Equal halves keep the divider on the fold, since the hinge API exposes no position.
struct SplitLayout: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            NavigationStack {
                QueueView(highlightsSelection: true)
            }
            .frame(maxWidth: .infinity)

            Divider().ignoresSafeArea()

            NavigationStack {
                if let id = store.selectedJobID {
                    JobDetailView(jobID: id)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(store.secondaryPane == .search ? "Search" : "History",
                                       systemImage: store.secondaryPane == .search ? "magnifyingglass" : "clock") {
                                    store.selectedJobID = nil
                                }
                            }
                        }
                        .id(id)
                } else {
                    Group {
                        switch store.secondaryPane {
                        case .history: HistoryView()
                        case .search: SearchView()
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Picker("Pane", selection: Bindable(store).secondaryPane) {
                                Text("History").tag(SecondaryPane.history)
                                Text("Search").tag(SecondaryPane.search)
                            }
                            .pickerStyle(.segmented)
                            .fixedSize()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
