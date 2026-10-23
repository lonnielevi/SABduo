import SwiftUI

@main struct SABduoApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                // .nzb files opened from Files or shared from another app ("Open in SABduo").
                .onOpenURL { url in
                    Task { await store.addNZB(from: url) }
                }
        }
    }
}
