import SwiftUI

struct HistoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.listRowFill) private var rowFill

    var body: some View {
        List {
            ForEach(store.history) { item in
                Button {
                    store.selectedHistoryID = item.id
                } label: {
                    HistoryRow(item: item)
                }
                .foregroundStyle(.primary)
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
        .navigationDestination(item: Bindable(store).selectedHistoryID) { id in
            HistoryDetailView(itemID: id)
                .railGap()
        }
    }
}

/// Clearing history by scope, each its own button. Each asks in a menu at the button, where a tap
/// anywhere else cancels; downloaded files are kept either way.
struct HistoryClearButtons: View {
    @Environment(AppStore.self) private var store
    @AppStorage(RemovalPrompt.storageKey) private var skipped = SkippedPrompts()
    /// The menus with "Don't ask again" ticked.
    @State private var dontAsk: Set<HistoryClearScope> = []

    var body: some View {
        Group {
            // The trash leads, as on the queue.
            button(.all, systemImage: "trash")
                .disabled(store.history.isEmpty)
            button(.completed, systemImage: "checkmark.circle")
                .disabled(!store.history.contains { $0.isCompleted })
            button(.failed, systemImage: "xmark.octagon")
                .disabled(!store.history.contains { $0.isFailed })
        }
        .disabled(!store.isConfigured)
    }

    @ViewBuilder
    private func button(_ scope: HistoryClearScope, systemImage: String) -> some View {
        let clear: () -> Void = { Task { await store.clearHistory(scope) } }
        let label = Label(scope.action, systemImage: systemImage)
        if skipped.asks(scope.prompt) {
            Menu {
                Section(scope.question) {
                    Button(scope.confirmation, systemImage: "trash", role: .destructive) {
                        if dontAsk.contains(scope) { skipped.skip(scope.prompt) }
                        clear()
                    }
                    DontAskAgainToggle(isOn: Binding(
                        get: { dontAsk.contains(scope) },
                        set: { if $0 { dontAsk.insert(scope) } else { dontAsk.remove(scope) } }
                    ))
                }
            } label: { label }
        } else {
            Button(action: clear) { label }
        }
    }
}

private extension HistoryClearScope {
    var prompt: RemovalPrompt {
        switch self {
        case .all: .clearAllHistory
        case .completed: .clearCompletedHistory
        case .failed: .clearFailedHistory
        }
    }

    var question: String {
        switch self {
        case .completed: "Clear completed downloads from history? Their files are kept."
        case .failed: "Clear failed downloads from history? Their files are kept."
        case .all: "Clear all history? Downloaded files are kept."
        }
    }

    /// The prompt's button, in sentence case like the rest of the prompt.
    var confirmation: String {
        switch self {
        case .completed: "Clear completed"
        case .failed: "Clear failed"
        case .all: "Clear all history"
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
