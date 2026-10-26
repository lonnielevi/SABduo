import SwiftUI

/// Pause/resume everything, plus the speed limit menu.
struct GlobalControls: View {
    @Environment(AppStore.self) private var store
    @State private var showingCustomLimit = false
    @State private var customLimit = ""

    private static let presetsMB = [1, 2, 5, 10, 25, 50]

    var body: some View {
        let paused = store.queue?.paused ?? false
        let limit = store.queue?.speedLimitBytes ?? 0

        Menu {
            Button {
                Task { await store.setSpeedLimit(bytesPerSecond: nil) }
            } label: {
                checkmarked("No Limit", limit == 0)
            }
            Section("Limit") {
                ForEach(Self.presetsMB, id: \.self) { mb in
                    Button {
                        Task { await store.setSpeedLimit(bytesPerSecond: mb * 1_048_576) }
                    } label: {
                        checkmarked("\(mb) MB/s", limit == mb * 1_048_576)
                    }
                }
                Button("Custom…", systemImage: "slider.horizontal.3") {
                    customLimit = limit > 0 ? Self.format(megabytes: Double(limit) / 1_048_576) : ""
                    showingCustomLimit = true
                }
            }
        } label: {
            Label("Speed Limit", systemImage: limit > 0 ? "gauge.with.dots.needle.33percent" : "gauge.with.dots.needle.100percent")
        }
        .tint(limit > 0 ? .orange : .primary)
        .disabled(!store.isConfigured)
        .alert("Speed Limit", isPresented: $showingCustomLimit) {
            TextField("MB/s", text: $customLimit)
                .keyboardType(.decimalPad)
            Button("Set") {
                let mb = Double(customLimit.replacingOccurrences(of: ",", with: ".")) ?? 0
                Task { await store.setSpeedLimit(bytesPerSecond: mb > 0 ? Int(mb * 1_048_576) : nil) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Megabytes per second. Leave empty for no limit.")
        }

        Button(paused ? "Resume All" : "Pause All", systemImage: paused ? "play.fill" : "pause.fill") {
            Task { await store.togglePauseAll() }
        }
        .disabled(!store.isConfigured)
    }

    @ViewBuilder
    private func checkmarked(_ title: String, _ selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private static func format(megabytes: Double) -> String {
        megabytes.formatted(.number.precision(.fractionLength(0...1)))
    }
}
