import SwiftUI

struct QueueRow: View {
    let job: QueueSlot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if job.isPaused {
                    Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
                }
                Text(job.filename.releaseNameWrapping)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                // A gap before the badge; without one, the name runs to the edge.
                Spacer(minLength: job.priority == .normal ? 0 : 8)
                if job.priority != .normal {
                    PriorityBadge(priority: job.priority)
                        .fixedSize()
                }
            }
            ProgressView(value: job.progress)
                .tint(job.isPaused ? .orange : .accentColor)
            HStack {
                Text("\(job.percentage)%")
                Text("·")
                Text("\(job.sizeLeft) of \(job.size) left")
                Spacer()
                Text(job.isPaused ? job.status : job.timeLeft)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct PriorityBadge: View {
    let priority: Priority

    var body: some View {
        Text(priority.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.18), in: .capsule)
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch priority {
        case .force: .red
        case .high: .orange
        case .normal: .secondary
        case .low: .blue
        }
    }
}

/// Shared by the row context menu and the detail view's toolbar.
struct JobMenu: View {
    @Environment(AppStore.self) private var store
    @AppStorage(RemovalPrompt.storageKey) private var skipped = SkippedPrompts()
    @State private var dontAsk = false
    let job: QueueSlot

    var body: some View {
        Button(job.isPaused ? "Resume" : "Pause", systemImage: job.isPaused ? "play.fill" : "pause.fill") {
            Task { await store.togglePause(job) }
        }
        Picker("Priority", systemImage: "flag", selection: Binding(
            get: { job.priority },
            set: { priority in Task { await store.setPriority(priority, for: job) } }
        )) {
            ForEach(Priority.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.menu)
        Button("Move to Top", systemImage: "arrow.up.to.line") {
            Task { await store.move(fromOffsets: [job.index(in: store.slots)], toOffset: 0) }
        }
        Button("Move to Bottom", systemImage: "arrow.down.to.line") {
            Task { await store.move(fromOffsets: [job.index(in: store.slots)], toOffset: store.slots.count) }
        }
        Divider()
        // Asks in a submenu, like clearing the queue, unless that's turned off.
        if skipped.asks(.deleteJob) {
            Menu("Delete", systemImage: "trash") {
                Section("Downloaded files for this job will be removed.") {
                    Button("Delete job and files", systemImage: "trash", role: .destructive) {
                        if dontAsk { skipped.skip(.deleteJob) }
                        delete()
                    }
                    DontAskAgainToggle(isOn: $dontAsk)
                }
            }
        } else {
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
        }
    }

    private func delete() {
        Task { await store.delete(job) }
    }
}

private extension QueueSlot {
    func index(in slots: [QueueSlot]) -> Int {
        slots.firstIndex { $0.id == id } ?? index
    }
}
