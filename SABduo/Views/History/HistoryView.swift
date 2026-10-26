import SwiftUI

struct HistoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.listRowFill) private var rowFill

    var body: some View {
        List {
            ForEach(store.history) { item in
                HistoryRow(item: item)
                    .listRowBackground(rowFill)
                    .swipeActions(edge: .trailing) {
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            Task { await store.remove(item) }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if item.canRetry {
                            Button("Retry", systemImage: "arrow.clockwise") {
                                Task { await store.retry(item) }
                            }
                            .tint(.blue)
                        }
                    }
                    .contextMenu {
                        if item.canRetry {
                            Button("Retry", systemImage: "arrow.clockwise") {
                                Task { await store.retry(item) }
                            }
                        }
                        Button("Remove from History", systemImage: "trash", role: .destructive) {
                            Task { await store.remove(item) }
                        }
                    }
            }
        }
        .overlay {
            if store.isConfigured, store.queue != nil, store.history.isEmpty {
                ContentUnavailableView("No History", systemImage: "clock")
                    .emptyStatePlacement()
            }
        }
        .refreshable { await store.refresh() }
        .navigationTitle("History")
        .listsToolbar()
    }
}

struct HistoryEditMenu: View {
    /// An icon wherever it is, like the buttons beside it; a word is wider, and in the folded
    /// bar pushes the buttons after it into an overflow menu.
    @Environment(AppStore.self) private var store

    var body: some View {
        Menu {
            Button("Clear Completed", systemImage: "checkmark.circle") { clear(.completed) }
                .disabled(!store.history.contains { $0.isCompleted })
            Button("Clear Failed", systemImage: "xmark.octagon") { clear(.failed) }
                .disabled(!store.history.contains { $0.isFailed })
            Divider()
            Button("Clear All History", systemImage: "trash", role: .destructive) { clear(.all) }
                .disabled(store.history.isEmpty)
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .disabled(!store.isConfigured)
    }

    /// Only history entries go; downloaded files are kept, so no confirmation.
    private func clear(_ scope: HistoryClearScope) {
        Task { await store.clearHistory(scope) }
    }
}
