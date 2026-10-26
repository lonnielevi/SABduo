import SwiftUI

/// SABnzbd's logged warnings and errors, newest first, with a button to clear them.
struct WarningsView: View {
    @Environment(AppStore.self) private var store
    @State private var warnings: [ServerWarning]?
    @State private var loadError: String?

    var body: some View {
        List {
            if let warnings {
                ForEach(warnings) { warning in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(warning.text, systemImage: warning.isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(warning.isError ? .red : .orange)
                            .textSelection(.enabled)
                        if let date = warning.date {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .overlay {
            if let loadError {
                ContentUnavailableView("Couldn't Load Warnings", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else if warnings?.isEmpty == true {
                ContentUnavailableView("No Warnings", systemImage: "checkmark.circle", description: Text("SABnzbd hasn't logged any."))
            } else if warnings == nil {
                ProgressView()
            }
        }
        .navigationTitle("Warnings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear", systemImage: "trash") {
                    Task { await clear() }
                }
                .disabled(warnings?.isEmpty != false)
            }
        }
        .refreshable { await load() }
        // Reload when SABnzbd logs another.
        .task(id: store.queue?.warningCount) { await load() }
    }

    private func load() async {
        guard let client = store.client else { return }
        do {
            warnings = try await client.warnings()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func clear() async {
        guard let client = store.client else { return }
        do {
            try await client.clearWarnings()
            withAnimation { warnings = [] }
            await store.refresh()
        } catch {
            loadError = error.localizedDescription
        }
    }
}
