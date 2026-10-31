import SwiftUI

/// A finished job: how long it took, which servers it came from, and what post-processing did.
struct HistoryDetailView: View {
    @Environment(AppStore.self) private var store
    @AppStorage(SpeedUnit.storageKey) private var unit: SpeedUnit = .megabytes
    let itemID: HistorySlot.ID

    var body: some View {
        if let item = store.history.first(where: { $0.id == itemID }) {
            content(item)
        } else {
            ContentUnavailableView("Removed from History", systemImage: "clock", description: Text("It's no longer in the history."))
                .emptyStatePlacement()
        }
    }

    private func content(_ item: HistorySlot) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.name.releaseNameWrapping)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                    Label(item.isCompleted || item.isFailed ? item.status : item.actionLine.nonEmpty ?? item.status,
                          systemImage: item.isCompleted ? "checkmark.circle.fill" : item.isFailed ? "xmark.octagon.fill" : "gearshape.2.fill")
                        .font(.subheadline)
                        .foregroundStyle(item.isCompleted ? .green : item.isFailed ? .red : .orange)
                    if item.isFailed, !item.failMessage.isEmpty {
                        Text(item.failMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Stats") {
                if item.downloadTime > 0 {
                    LabeledContent("Download", value: Self.duration(item.downloadTime))
                    if item.bytes > 0 {
                        LabeledContent("Average Speed", value: unit.format(Double(item.bytes) / Double(item.downloadTime)))
                    }
                }
                if item.postprocTime > 0 {
                    LabeledContent("Post-Processing", value: Self.duration(item.postprocTime))
                }
                if item.downloadTime > 0, item.postprocTime > 0 {
                    LabeledContent("Total", value: Self.duration(item.downloadTime + item.postprocTime))
                }
                if let completed = item.completed {
                    LabeledContent("Finished", value: completed.formatted(date: .abbreviated, time: .shortened))
                }
            }

            if let servers = item.stages.first(where: { $0.name == "Servers" }), !servers.actions.isEmpty {
                Section("Servers") {
                    ForEach(servers.actions, id: \.self) { line in
                        // "host=1.2 GB"
                        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                        if parts.count == 2 {
                            LabeledContent(parts[0], value: parts[1])
                        } else {
                            Text(line)
                        }
                    }
                }
            }

            ForEach(stepStages(item), id: \.self) { stage in
                Section(stage.name) {
                    ForEach(stage.actions, id: \.self) { line in
                        Text(line)
                            .font(.subheadline)
                            .textSelection(.enabled)
                    }
                }
            }

            Section("Details") {
                if !item.size.isEmpty { LabeledContent("Size", value: item.size) }
                if !item.category.isEmpty, item.category != "*", item.category != "None" {
                    LabeledContent("Category", value: item.category)
                }
                if !item.script.isEmpty, item.script != "None" { LabeledContent("Script", value: item.script) }
                if !item.nzbName.isEmpty { detail("NZB", item.nzbName) }
                if !item.storage.isEmpty { detail("Location", item.storage) }
            }

            Section {
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
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        // The job's name heads the page already; the title stays for the back button and VoiceOver.
        .toolbar(removing: .title)
    }

    /// The steps after the servers, as SABnzbd names them. The download's own time and speed are
    /// in Stats, and the source is the NZB in Details.
    private func stepStages(_ item: HistorySlot) -> [HistorySlot.Stage] {
        item.stages.compactMap { stage in
            guard !["Servers", "Source"].contains(stage.name) else { return nil }
            var stage = stage
            if stage.name == "Download" {
                stage.actions.removeAll { $0.hasPrefix("Downloaded in") }
            }
            // "[name] Quick Check OK": the name heads the page already.
            stage.actions = stage.actions.map { $0.replacing(/^\[[^\]]*\]\s*/, with: "") }
            return stage.actions.isEmpty ? nil : stage
        }
    }

    /// Long values beneath their label, where they can wrap.
    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private static func duration(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
    }
}
