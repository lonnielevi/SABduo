import SwiftUI

struct JobDetailView: View {
    @Environment(AppStore.self) private var store
    let jobID: QueueSlot.ID
    @State private var confirmingDelete = false

    var body: some View {
        if let job = store.job(jobID) {
            content(job)
        } else {
            ContentUnavailableView("Job Finished or Removed", systemImage: "checkmark.circle", description: Text("It's no longer in the queue. Check History."))
                .emptyStatePlacement()
        }
    }

    private func content(_ job: QueueSlot) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(job.filename)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                    ProgressView(value: job.progress) {
                        HStack {
                            Text("\(job.percentage)%").font(.headline.monospacedDigit())
                            Spacer()
                            Text(job.isPaused ? "Paused" : job.timeLeft)
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(job.isPaused ? .orange : .accentColor)
                }
                .padding(.vertical, 4)
            }

            Section {
                Button(job.isPaused ? "Resume" : "Pause", systemImage: job.isPaused ? "play.fill" : "pause.fill") {
                    Task { await store.togglePause(job) }
                }
                Picker("Priority", systemImage: "flag", selection: Binding(
                    get: { job.priority },
                    set: { priority in Task { await store.setPriority(priority, for: job) } }
                )) {
                    ForEach(Priority.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Details") {
                LabeledContent("Status", value: job.status)
                LabeledContent("Size", value: job.size)
                LabeledContent("Remaining", value: job.sizeLeft)
                LabeledContent("Time Left", value: job.timeLeft)
                LabeledContent("Position", value: "\(job.index + 1) of \(store.slots.count)")
                if !job.averageAge.isEmpty { LabeledContent("Age", value: job.averageAge) }
                if !job.category.isEmpty, job.category != "*", job.category != "None" {
                    LabeledContent("Category", value: job.category)
                }
            }

            Section {
                Button("Delete Job", systemImage: "trash", role: .destructive) {
                    confirmingDelete = true
                }
            }
        }
        .navigationTitle("Job")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Actions", systemImage: "ellipsis") {
                    JobMenu(job: job, onDelete: { confirmingDelete = true })
                }
            }
        }
        .confirmationDialog("Delete \(job.filename)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Job and Files", role: .destructive) {
                Task { await store.delete(job) }
            }
        } message: {
            Text("Downloaded files for this job will be removed.")
        }
    }
}
