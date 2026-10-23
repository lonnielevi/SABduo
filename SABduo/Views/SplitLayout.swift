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

            Group {
                if let id = store.selectedJobID {
                    NavigationStack {
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
                    }
                } else {
                    switch store.secondaryPane {
                    case .history:
                        NavigationStack {
                            HistoryView().secondaryPanePicker(true)
                        }
                    case .search:
                        SearchStack(showsPanePicker: true)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// History/Search switcher for the root of the trailing pane. It stands in for the title:
/// a large title there sits flush against the divider.
private struct SecondaryPanePicker: ViewModifier {
    @Environment(AppStore.self) private var store

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
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

extension View {
    @ViewBuilder
    func secondaryPanePicker(_ enabled: Bool) -> some View {
        if enabled { modifier(SecondaryPanePicker()) } else { self }
    }
}
