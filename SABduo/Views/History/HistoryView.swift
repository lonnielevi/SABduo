import SwiftUI

struct HistoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.listRowFill) private var rowFill

    var body: some View {
        List {
            ForEach(store.history) { item in
                HistoryRow(item: item)
                    .listRowBackground(rowFill)
                    // Swipe left only, clear of the back gesture; the gentler action at the edge.
                    .swipeActions(allowsFullSwipe: false) {
                        if item.canRetry {
                            Button("Retry", systemImage: "arrow.clockwise") {
                                Task { await store.retry(item) }
                            }
                            .tint(.blue)
                        }
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            Task { await store.remove(item) }
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
        .opacity(store.isOffline ? 0 : 1)
        .overlay {
            if store.isOffline {
                ServerUnreachableView()
            } else if store.isConfigured, store.queue != nil, store.history.isEmpty {
                ContentUnavailableView("No History", systemImage: "clock")
                    .emptyStatePlacement()
            }
        }
        .refreshable { await store.refresh() }
        .navigationTitle("History")
        .listsToolbar()
    }
}

/// Clearing history by scope, each its own button. Each asks in a menu at the button, where a tap
/// anywhere else cancels; downloaded files are kept either way.
struct HistoryClearButtons: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            button(.completed, systemImage: "checkmark.circle")
                .disabled(!store.history.contains { $0.isCompleted })
            button(.failed, systemImage: "xmark.octagon")
                .disabled(!store.history.contains { $0.isFailed })
            button(.all, systemImage: "trash")
                .disabled(store.history.isEmpty)
        }
        .disabled(!store.isConfigured)
    }

    private func button(_ scope: HistoryClearScope, systemImage: String) -> some View {
        Menu {
            Section(scope.question) {
                Button(scope.action, systemImage: "trash", role: .destructive) {
                    Task { await store.clearHistory(scope) }
                }
            }
        } label: {
            Label(scope.action, systemImage: systemImage)
        }
    }
}

private extension HistoryClearScope {
    var question: String {
        switch self {
        case .completed: "Clear completed downloads from history? Their files are kept."
        case .failed: "Clear failed downloads from history? Their files are kept."
        case .all: "Clear all history? Downloaded files are kept."
        }
    }

    var action: String {
        switch self {
        case .completed: "Clear Completed"
        case .failed: "Clear Failed"
        case .all: "Clear All History"
        }
    }
}
