import SwiftUI

@main struct SABduoApp: App {
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
