import SwiftUI

/// A small green or red light: whether a server answered. Grey and pulsing while still waiting
/// for the first answer.
struct ConnectionLight: View {
    /// True when connected, false when not, nil while checking.
    let state: Bool?
    let name: String

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 9))
            .foregroundStyle(state.map { $0 ? Color.green : .red } ?? .secondary)
            .symbolEffect(.pulse, isActive: state == nil)
            .animation(.default, value: state)
            .accessibilityLabel(name)
            .accessibilityValue(state.map { $0 ? "Connected" : "Not connected" } ?? "Connecting")
    }
}

/// The SABnzbd server's light. Red when no server is set up.
struct ServerConnectionLight: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ConnectionLight(state: store.isConfigured ? store.isConnected : false, name: "SABnzbd")
    }
}
