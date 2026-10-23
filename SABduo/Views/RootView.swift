import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in SABduo-Info.plist as an imported type.
    static let nzb = UTType(importedAs: "com.newzbin.nzb", conformingTo: .xml)
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var hinge: HingeState?
    @State private var showingSettings = false
    @State private var showingImporter = false

    /// Cover display is 466pt wide, the inner display 669pt (portrait) or 951pt (landscape).
    private static let splitMinWidth: CGFloat = 600

    var body: some View {
        GeometryReader { proxy in
            Group {
                if isUnfolded(width: proxy.size.width) {
                    SplitLayout()
                } else {
                    CompactLayout()
                }
            }
            .animation(.default, value: isUnfolded(width: proxy.size.width))
        }
        .readHinge(into: $hinge)
        .environment(\.rootActions, RootActions(
            showSettings: { showingSettings = true },
            addNZB: { showingImporter = true }
        ))
        .safeAreaInset(edge: .bottom) { StatusBanner() }
        .task(id: scenePhase) {
            // Poll only while the app is in the foreground; leaving cancels the task.
            guard scenePhase == .active else { return }
            await store.poll()
        }
        .onAppear {
            if !store.isConfigured { showingSettings = true }
        }
        .sheet(isPresented: $showingSettings) {
            ServerSettingsView()
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.nzb], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task {
                for url in urls { await store.addNZB(from: url) }
            }
        }
    }

    private func isUnfolded(width: CGFloat) -> Bool {
        let roomy = width >= Self.splitMinWidth
        switch hinge {
        case .open: return roomy
        case .closed: return false
        case nil: return roomy && sizeClass == .regular
        }
    }
}

/// Lets toolbars deep in either layout trigger sheets owned by `RootView`,
/// so presentations survive a fold/unfold that swaps the layout.
struct RootActions {
    var showSettings: () -> Void = {}
    var addNZB: () -> Void = {}
}

extension EnvironmentValues {
    @Entry var rootActions = RootActions()
}

/// Non-modal error and confirmation strip; polling errors repeat, so an alert would nag.
private struct StatusBanner: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 8) {
            if let error = store.errorMessage {
                banner(error, systemImage: "exclamationmark.triangle.fill", tint: .red) {
                    store.errorMessage = nil
                }
            }
            if let notice = store.notice {
                banner(notice, systemImage: "checkmark.circle.fill", tint: .green) {
                    store.notice = nil
                }
                .task(id: notice) {
                    try? await Task.sleep(for: .seconds(3))
                    store.notice = nil
                }
            }
        }
        .padding(.horizontal)
        .animation(.default, value: store.errorMessage)
        .animation(.default, value: store.notice)
    }

    private func banner(_ text: String, systemImage: String, tint: Color, dismiss: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(text, systemImage: systemImage)
                .font(.callout)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
