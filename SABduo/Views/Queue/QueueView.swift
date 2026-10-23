import SwiftUI

struct QueueView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.rootActions) private var actions
    /// In the split layout the detail sits beside the list, so mark the open job.
    var highlightsSelection = false
    @State private var pendingDelete: QueueSlot?

    var body: some View {
        List {
            Section {
                QueueSummary()
            }

            Section {
                ForEach(store.slots) { job in
                    Button {
                        store.selectedJobID = job.id
                    } label: {
                        QueueRow(job: job)
                    }
                    .foregroundStyle(.primary)
                    .listRowBackground(highlightsSelection && store.selectedJobID == job.id ? Color.accentColor.opacity(0.15) : nil)
                    .swipeActions(edge: .leading) {
                        Button(job.isPaused ? "Resume" : "Pause", systemImage: job.isPaused ? "play.fill" : "pause.fill") {
                            Task { await store.togglePause(job) }
                        }
                        .tint(job.isPaused ? .green : .orange)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            pendingDelete = job
                        }
                    }
                    .contextMenu { JobMenu(job: job, onDelete: { pendingDelete = job }) }
                }
                .onMove { source, destination in
                    Task { await store.move(fromOffsets: source, toOffset: destination) }
                }
            }
        }
        .overlay {
            if store.isConfigured, store.queue != nil, store.slots.isEmpty {
                ContentUnavailableView("Queue Empty", systemImage: "tray", description: Text("Add an NZB from Files or the share sheet."))
            } else if !store.isConfigured {
                ContentUnavailableView {
                    Label("No Server", systemImage: "server.rack")
                } actions: {
                    Button("Set Up Server", action: actions.showSettings)
                }
            }
        }
        .refreshable { await store.refresh() }
        .navigationTitle("Queue")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Server", systemImage: "gearshape", action: actions.showSettings)
            }
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                GlobalControls()
                Button("Add NZB", systemImage: "plus", action: actions.addNZB)
                    .disabled(!store.isConfigured)
            }
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.filename ?? "job")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { job in
            Button("Delete Job and Files", role: .destructive) {
                Task { await store.delete(job) }
            }
        } message: { _ in
            Text("Downloaded files for this job will be removed.")
        }
    }
}

/// Overall speed, remaining size and ETA for the whole queue.
private struct QueueSummary: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let queue = store.queue
        HStack(spacing: 16) {
            stat(
                queue.map { $0.paused ? "Paused" : Self.rate($0.bytesPerSecond) } ?? "–",
                caption: "Speed",
                systemImage: queue?.paused == true ? "pause.circle.fill" : "arrow.down"
            )
            stat(queue?.sizeLeft.nonEmpty ?? "–", caption: "Left", systemImage: "externaldrive")
            stat(queue?.timeLeft.nonEmpty ?? "–", caption: "ETA", systemImage: "clock")
            if let limit = queue?.speedLimitBytes, limit > 0 {
                stat(Self.rate(Double(limit)), caption: "Limit", systemImage: "gauge.with.dots.needle.33percent")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ value: String, caption: String, systemImage: String) -> some View {
        // Values stay on one line: each half of the unfolded Duo is only ~335pt wide.
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Label(caption, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .binary) + "/s"
    }
}

nonisolated extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
