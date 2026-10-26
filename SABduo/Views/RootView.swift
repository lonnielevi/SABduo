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
    @State private var showingImporter = false

    /// Cover display is 466pt wide, the inner display 669pt (portrait) or 951pt (landscape).
    private static let splitMinWidth: CGFloat = 600

    var body: some View {
        GeometryReader { proxy in
            let unfolded = isUnfolded(width: proxy.size.width)
            Group {
                if unfolded {
                    SplitLayout(isBook: hinge == .book)
                } else {
                    CompactLayout()
                }
            }
            .animation(.default, value: unfolded)
            // Folded, the app stays upright: the cover display is too short for landscape.
            .onChange(of: unfolded, initial: true) { AppDelegate.allowLandscape(unfolded) }
        }
        // Never shorten the layouts for the keyboard: the unfolded bars hang off their bottom,
        // and a keyboard's space can outlive a rotation. Views inside still see the keyboard's
        // inset and make room for it where they take text.
        .ignoresSafeArea(.keyboard)
        .readHinge(into: $hinge)
        .environment(\.rootActions, RootActions(
            showSettings: { store.showSettings() },
            addNZB: { showingImporter = true }
        ))
        // Settings shows connection errors in its form instead, clear of its buttons.
        .safeAreaInset(edge: .bottom) {
            StatusBanner(showsError: !store.settingsOnScreen)
        }
        .task(id: scenePhase) {
            // Poll only while the app is in the foreground; leaving cancels the task.
            guard scenePhase == .active else { return }
            await store.poll()
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
        case .open, .book: return roomy
        case .closed: return false
        case nil: return roomy && sizeClass == .regular
        }
    }
}

extension UIApplication {
    /// The interface orientation, not the layout's shape: the keyboard shortens the layout, and in
    /// portrait that can leave it wider than tall.
    static var interfaceIsLandscape: Bool {
        let scene = shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }.first
        return scene?.effectiveGeometry.interfaceOrientation.isLandscape ?? false
    }

    /// Where the clock sits. The scene reports no useful status bar frame on the Duo, so it's
    /// measured from the top inset, whose last 34pt lie below the clock's centre.
    static var statusBarMidY: CGFloat {
        max(windowTopInset - 34, 28)
    }

    /// The window's top safe area inset.
    static var windowTopInset: CGFloat {
        shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.safeAreaInsets.top ?? 0
    }
}

/// Lets toolbars deep in either layout trigger presentations owned by `RootView`,
/// so they survive a fold/unfold that swaps the layout.
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
    var showsError = true

    var body: some View {
        VStack(spacing: 8) {
            if showsError, let error = store.errorMessage {
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
