import SwiftUI

struct QueueView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.rootActions) private var actions
    /// In the split layout the detail sits beside the list, so mark the open job.
    var highlightsSelection = false
    @State private var pendingDelete: QueueSlot?
    @Environment(\.listRowFill) private var rowFill

    var body: some View {
        // The stats sit above the pages instead (see `QueueStatsCard`).
        List {
            Section {
                ForEach(store.slots) { job in
                    Button {
                        store.selectedJobID = job.id
                    } label: {
                        QueueRow(job: job)
                    }
                    .foregroundStyle(.primary)
                    .listRowBackground(highlightsSelection && store.selectedJobID == job.id ? Color.accentColor.opacity(0.15) : rowFill)
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
                ContentUnavailableView("Queue Empty", systemImage: "tray", description: Text("Add an NZB from Search, Files, or the Share Sheet."))
                    .emptyStatePlacement()
            } else if !store.isConfigured {
                ContentUnavailableView {
                    Label("No Server", systemImage: "server.rack")
                } actions: {
                    Button("Set Up Server", action: actions.showSettings)
                }
                .emptyStatePlacement()
            }
        }
        .environment(\.editMode, Binding(
            get: { store.isReorderingQueue ? .active : .inactive },
            set: { store.isReorderingQueue = $0.isEditing }
        ))
        .refreshable { await store.refresh() }
        .navigationTitle("Queue")
        .listsToolbar()
        .confirmationDialog(
            "Clear the queue?",
            isPresented: Bindable(store).confirmingClearQueue,
            titleVisibility: .visible
        ) {
            Button("Delete All \(store.slots.count) Jobs and Files", role: .destructive) {
                Task { await store.clearQueue() }
            }
        } message: {
            Text("Every job in the queue and its downloaded files will be removed.")
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

/// The queue's stats in a card, heading every page above the page picker.
struct QueueStatsCard: View {
    /// Stands out from what's behind it: grey on the unfolded list pane's white, white on grey.
    var fill = Color(.secondarySystemGroupedBackground)
    /// Folded, the tab bar can't show the server's light beside Queue, so the stats carry it.
    var showsServerLight = false

    static let height: CGFloat = 56

    var body: some View {
        HStack {
            QueueSummary()
            if showsServerLight { ServerConnectionLight() }
        }
        .padding(.horizontal, 20)
        .frame(height: Self.height)
        .background(fill, in: .rect(cornerRadius: 24))
    }
}

/// Overall speed, remaining size, jobs and time left for the whole queue.
struct QueueSummary: View {
    @Environment(AppStore.self) private var store
    @AppStorage(SpeedUnit.storageKey) private var unit: SpeedUnit = .megabytes
    @AppStorage(TimeLeftStyle.storageKey) private var timeStyle: TimeLeftStyle = .countdown

    var body: some View {
        // One size for every stat: the largest at which they all fit, rather than each shrinking
        // on its own and ending up a different size from its neighbours.
        ViewThatFits(in: .horizontal) {
            stats.font(.headline)
            stats.font(.subheadline.weight(.semibold))
            stats.font(.footnote.weight(.semibold))
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Each stat as wide as it needs, spread evenly across the card.
    private var stats: some View {
        let queue = store.queue
        return HStack(spacing: 0) {
            // Tapping the speed steps through the units; Settings picks one outright.
            Button {
                withAnimation(.snappy) { unit = unit.next }
            } label: {
                stat(
                    queue.map { $0.paused ? "Paused" : unit.format($0.bytesPerSecond) } ?? "–",
                    caption: "Speed"
                )
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the speed in \(unit.next.name.lowercased())")
            Spacer(minLength: 12)
            stat(queue?.sizeLeft.nonEmpty ?? "–", caption: "Queued")
            Spacer(minLength: 12)
            stat(queue.map { $0.jobCount == 1 ? "1 Job" : "\($0.jobCount) Jobs" } ?? "–", caption: "Jobs")
            Spacer(minLength: 12)
            // Tapping swaps the countdown for the time it'll finish, and back.
            Button {
                withAnimation(.snappy) { timeStyle = timeStyle.other }
            } label: {
                timeLeft(queue).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the \(timeStyle.other.name.lowercased())")
            if let limit = queue?.speedLimitBytes, limit > 0 {
                Spacer(minLength: 12)
                stat(unit.format(Double(limit)), caption: "Limit")
            }
        }
    }

    @ViewBuilder
    private func timeLeft(_ queue: Queue?) -> some View {
        switch timeStyle {
        case .countdown:
            stat(queue.flatMap { $0.secondsLeft != nil ? $0.timeLeft : nil } ?? "–", caption: "Finishes In")
        case .finishTime:
            stat(finishTime(queue) ?? "–", caption: "Finishes At")
        }
    }

    /// When the queue will finish at the current speed: "4:12 PM", or "Sat 4:12 PM" after today.
    private func finishTime(_ queue: Queue?) -> String? {
        guard let queue, !queue.paused, let seconds = queue.secondsLeft else { return nil }
        let finish = (store.lastUpdated ?? .now).addingTimeInterval(TimeInterval(seconds))
        return Calendar.current.isDateInToday(finish)
            ? finish.formatted(date: .omitted, time: .shortened)
            : finish.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private func stat(_ value: String, caption: String) -> some View {
        // Values alone, on one line, in the row's font. The caption is for VoiceOver.
        Text(value)
            .lineLimit(1)
            .fixedSize()
            .contentTransition(.numericText())
            .accessibilityLabel(caption)
            .accessibilityValue(value)
    }
}

nonisolated extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

struct QueueEditMenu: View {
    /// An icon wherever it is, like the buttons beside it; a word is wider, and in the folded
    /// bar pushes the buttons after it into an overflow menu.
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.isReorderingQueue {
            Button("Done") { withAnimation { store.isReorderingQueue = false } }
            .bold()
        } else {
            Menu {
                Button("Reorder Queue") {
                    withAnimation { store.isReorderingQueue = true }
                }
                .disabled(store.slots.count < 2)
                Divider()
                Button("Clear Queue…", systemImage: "trash", role: .destructive) {
                    store.confirmingClearQueue = true
                }
                .disabled(store.slots.isEmpty)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .disabled(!store.isConfigured)
        }
    }
}
