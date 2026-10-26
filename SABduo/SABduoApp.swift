import SwiftUI

@main struct SABduoApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var store = AppStore()
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(appearance.colorScheme)
                // .nzb files opened from Files or shared from another app ("Open in SABduo").
                .onOpenURL { url in
                    Task { await store.addNZB(from: url) }
                }
        }
    }
}

/// Supplies the orientations the interface may take, which depend on whether the Duo is folded.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Folded, the cover display stays upright; unfolded, the inner display turns freely.
    @MainActor static var orientations: UIInterfaceOrientationMask = .allButUpsideDown

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientations
    }

    /// Allows landscape or not, turning the interface upright now if it's sideways.
    @MainActor static func allowLandscape(_ allowed: Bool) {
        orientations = allowed ? .allButUpsideDown : .portrait
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
        }
    }
}
