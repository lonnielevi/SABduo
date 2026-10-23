import SwiftUI

struct HistoryView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            ForEach(store.history) { item in
                HistoryRow(item: item)
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
            }
        }
        .refreshable { await store.refresh() }
        .navigationTitle("History")
    }
}
