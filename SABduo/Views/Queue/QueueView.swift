import SwiftUI

struct QueueView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.rootActions) private var actions
    /// In the split layout the detail sits beside the list, so mark the open job.
    var highlightsSelection = false
    @State private var pendingDelete: QueueSlot.ID?
    @AppStorage(RemovalPrompt.storageKey) private var skipped = SkippedPrompts()
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
                    // Swipe left only, clear of the back gesture; the gentler action at the edge.
                    .swipeActions(allowsFullSwipe: false) {
                        Button(job.isPaused ? "Resume" : "Pause", systemImage: job.isPaused ? "play.fill" : "pause.fill") {
                            Task { await store.togglePause(job) }
                        }
                        .tint(job.isPaused ? .green : .orange)
                        // Not `.destructive`: that slides the row away before the prompt asks.
                        Button("Delete", systemImage: "trash") {
                            delete(job)
                        }
                        .tint(.red)
                    }
                    .contextMenu { JobMenu(job: job) }
                    // On the row, so the prompt points at the job.
                    .confirmationDialog(
                        "Delete \(job.filename)?",
                        isPresented: Binding(
                            get: { pendingDelete == job.id },
                            set: { if !$0 { pendingDelete = nil } }
                        ),
                        titleVisibility: .visible
                    ) {
                        Button("Delete job and files", role: .destructive) {
                            Task { await store.delete(job) }
                        }
                        Button("Delete and don't ask again", role: .destructive) {
                            skipped.skip(.deleteJob)
                            Task { await store.delete(job) }
                        }
                    } message: {
                        Text("Downloaded files for this job will be removed.")
                    }
                }
                .onMove { source, destination in
                    Task { await store.move(fromOffsets: source, toOffset: destination) }
                }
            }
        }
        // A list from before the server stopped answering would be stale.
        .opacity(store.isOffline ? 0 : 1)
        .overlay {
            if store.isOffline {
                ServerUnreachableView()
            } else if store.isConfigured, store.queue != nil, store.slots.isEmpty {
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
        .refreshable { await store.refresh() }
        .navigationTitle("Queue")
        .listsToolbar()
    }

    /// Asks first, unless that prompt is turned off.
    private func delete(_ job: QueueSlot) {
        if skipped.asks(.deleteJob) {
            pendingDelete = job.id
        } else {
            Task { await store.delete(job) }
        }
    }
}

/// The queue's stats in a card, heading every page above the page picker.
struct QueueStatsCard: View {
    @Environment(AppStore.self) private var store
    /// Folded, the tab bar can't show the server's light beside Queue, so the stats carry it.
    var showsServerLight = false

    /// The speed line's height, for lining it up with the status bar's clock.
    static let height: CGFloat = 41

    var body: some View {
        // Once SABnzbd has answered; with nothing to download, it's the app's name.
        if store.queue != nil {
            QueueSummary(showsServerLight: showsServerLight)
                // In line with the cards' edges, as a large title is.
                .padding(.horizontal, 4)
        }
    }
}

/// The queue's stats, styled as a large title: the speed, and beneath it what's left, the jobs
/// and the time. Tapping the speed steps through its units; tapping the time swaps the countdown
/// for when it'll finish.
struct QueueSummary: View {
    @Environment(AppStore.self) private var store
    @AppStorage(SpeedUnit.storageKey) private var unit: SpeedUnit = .megabytes
    var showsServerLight = false

    var body: some View {
        let queue = store.queue
        // With nothing downloading, the app's name stands in for a speed of nothing.
        let isIdle = queue.map { !$0.paused && $0.bytesPerSecond == 0 } ?? false
        let isEmpty = (queue?.jobCount ?? 0) == 0
        VStack(alignment: .leading, spacing: 0) {
            Button {
                // Plain, not disabled, so the name isn't dimmed.
                guard !isIdle else { return }
                withAnimation(.snappy) { unit = unit.next }
            } label: {
                Text(isIdle ? "SABduo" : queue.map { $0.paused ? "Paused" : unit.format($0.bytesPerSecond) } ?? "–")
                    .font(.largeTitle.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                    .frame(height: QueueStatsCard.height, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isIdle ? "SABduo" : "Speed")
            .accessibilityHint(isIdle ? "" : "Shows the speed in \(unit.next.name.lowercased())")

            if isEmpty {
                // An empty queue says so itself; beneath the name, the server it's from.
                HStack(spacing: 6) {
                    Text(store.config.normalizedHost)
                    if showsServerLight { ServerConnectionLight() }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            } else {
                QueueDetailsLine(showsServerLight: showsServerLight)
            }
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}


/// Beneath the speed: "53.6 GB left · 6 jobs · 1h 16m", any limit, and the server's light, a
/// size smaller when it won't fit. Tapping the time swaps the countdown for when it'll finish.
struct QueueDetailsLine: View {
    @Environment(AppStore.self) private var store
    @AppStorage(SpeedUnit.storageKey) private var unit: SpeedUnit = .megabytes
    @AppStorage(TimeLeftStyle.storageKey) private var timeStyle: TimeLeftStyle = .countdown
    var showsServerLight = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            details(store.queue).font(.subheadline)
            details(store.queue).font(.footnote)
        }
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    /// "53.6 GB left · 6 jobs · 1h 16m", and the server's light.
    private func details(_ queue: Queue?) -> some View {
        HStack(spacing: 6) {
            Text(queue.map { $0.sizeLeft.isEmpty ? "Nothing left" : "\($0.sizeLeft) left" } ?? "–")
            Text("·")
            Text(queue.map { $0.jobCount == 1 ? "1 job" : "\($0.jobCount) jobs" } ?? "–")
            if queue?.secondsLeft != nil {
                Text("·")
                Button {
                    withAnimation(.snappy) { timeStyle = timeStyle.other }
                } label: {
                    timeLeft(queue).contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the \(timeStyle.other.name.lowercased())")
            }
            if let limit = queue?.speedLimitBytes, limit > 0 {
                Text("·")
                Text("Limit \(unit.format(Double(limit)))")
            }
            if showsServerLight { ServerConnectionLight() }
        }
        .lineLimit(1)
        .fixedSize()
        .contentTransition(.numericText())
    }

    @ViewBuilder
    private func timeLeft(_ queue: Queue?) -> some View {
        switch timeStyle {
        case .countdown:
            Text(Self.countdown(queue) ?? "–").accessibilityLabel("Finishes in")
        case .finishTime:
            Text(Self.finishTime(queue, lastUpdated: store.lastUpdated) ?? "–").accessibilityLabel("Finishes at")
        }
    }

    /// "1h 16m", or "2d 3h" for a long queue, or seconds under a minute.
    static func countdown(_ queue: Queue?) -> String? {
        guard let seconds = queue?.secondsLeft else { return nil }
        let units: Set<Duration.UnitsFormatStyle.Unit> = seconds >= 86_400 ? [.days, .hours]
            : seconds >= 60 ? [.hours, .minutes] : [.seconds]
        return Duration.seconds(seconds).formatted(.units(allowed: units, width: .narrow, maximumUnitCount: 2))
    }

    /// When the queue will finish at the current speed: "4:12 PM", or "Sat 4:12 PM" after today.
    static func finishTime(_ queue: Queue?, lastUpdated: Date?) -> String? {
        guard let queue, !queue.paused, let seconds = queue.secondsLeft else { return nil }
        let finish = (lastUpdated ?? .now).addingTimeInterval(TimeInterval(seconds))
        return Calendar.current.isDateInToday(finish)
            ? finish.formatted(date: .omitted, time: .shortened)
            : finish.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

nonisolated extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// Clears the queue, after asking in a menu at the button: a tap anywhere else cancels. Jobs
/// reorder by pressing and holding one, then dragging it.
struct ClearQueueButton: View {
    @Environment(AppStore.self) private var store
    @AppStorage(RemovalPrompt.storageKey) private var skipped = SkippedPrompts()
    @State private var dontAsk = false

    var body: some View {
        let label = Label("Clear Queue", systemImage: "trash")
        Group {
            if skipped.asks(.clearQueue) {
                Menu {
                    Section("Every job in the queue and its downloaded files will be removed.") {
                        Button("Delete all \(store.slots.count) jobs and files", systemImage: "trash", role: .destructive) {
                            if dontAsk { skipped.skip(.clearQueue) }
                            clear()
                        }
                        DontAskAgainToggle(isOn: $dontAsk)
                    }
                } label: { label }
            } else {
                Button(action: clear) { label }
            }
        }
        .disabled(!store.isConfigured || store.slots.isEmpty)
    }

    private func clear() {
        Task { await store.clearQueue() }
    }
}

/// In a removal's menu, ticked before its button: once that goes ahead, the menu stops asking.
/// Settings' Reset Prompts brings it back. The menu stays open while it's ticked.
///
/// A button with its own circle rather than a `Toggle`: a menu's checkmark adds a column when it
/// appears, which shifts every row across.
struct DontAskAgainToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button("Don't ask again", systemImage: isOn ? "checkmark.circle.fill" : "circle") {
            isOn.toggle()
        }
        .menuActionDismissBehavior(.disabled)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
