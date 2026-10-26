import SwiftUI

/// Folded: one page at a time, picked from the tab bar, which the cover display puts in the side rail: Search,
/// Queue, History and Settings. A job opens over the queue.
struct CompactLayout: View {
    @Environment(AppStore.self) private var store
    @State private var page: Page = .queue

    var body: some View {
        TabView(selection: Binding(get: { page }, set: show)) {
            // A plain tab at the top of the rail, as in Apple Music's sidebar, rather than the search
            // role's tab apart at the end. Its field runs across the top of its pages.
            if store.showsSearch {
                Tab(Page.search.title, systemImage: Page.search.systemImage, value: .search) {
                    SearchStack { header }
                }
            }
            Tab(Page.queue.title, systemImage: Page.queue.systemImage, value: .queue) {
                // The path mirrors `selectedJobID`, so a job opened while unfolded stays open after folding.
                NavigationStack(path: selectionPath) {
                    QueueView()
                        .topPage(header)
                        .navigationDestination(for: QueueSlot.ID.self) { id in
                            JobDetailView(jobID: id)
                        }
                }
            }
            Tab(Page.history.title, systemImage: Page.history.systemImage, value: .history) {
                NavigationStack {
                    HistoryView()
                        .topPage(header)
                }
            }
            Tab(Page.settings.title, systemImage: Page.settings.systemImage, value: .settings) {
                NavigationStack {
                    ServerSettingsView()
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar(removing: .title)
                        .topPage(header)
                }
            }
        }
        // The cover display keeps a side rail, beside the status bar.
        .environment(\.usesBottomBar, false)
        .onAppear {
            // Carry over what was in use when unfolded: an open job, then a search in progress,
            // then whichever page the leading side was showing.
            if store.selectedJobID != nil {
                page = .queue
            } else if store.showsSearch, !store.search.path.isEmpty || store.search.homeFeed.hasLoaded {
                page = .search
            } else {
                page = Page(store.listPane)
            }
        }
        // Buttons elsewhere that open Settings: setting up a server, adding an indexer.
        .onChange(of: store.settingsRequests) { show(.settings) }
        // Hiding search leaves its tab; land on the queue.
        .onChange(of: store.showsSearch) { if !store.showsSearch, page == .search { show(.queue) } }
    }

    /// The download stats, heading each page in a bar inside its navigation, so lists scroll
    /// beneath them. The tab bar has no room for the server's light, so they carry it.
    private var header: some View {
        QueueStatsCard(showsServerLight: true)
            .railPageMargins()
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private func show(_ new: Page) {
        page = new
        // Also the page to land on when unfolding.
        if let pane = new.listPane { store.listPane = pane }
    }

    private var selectionPath: Binding<[QueueSlot.ID]> {
        Binding(
            get: { store.selectedJobID.map { [$0] } ?? [] },
            set: { store.selectedJobID = $0.last }
        )
    }
}

private extension View {
    /// A page the tab bar opens, headed by the stats. The page is grey with white cards like
    /// search's, even with nothing in it.
    func topPage(_ header: some View) -> some View {
        safeAreaBar(edge: .top) { header }
            // A gap under the stats, like the unfolded pane's under its picker.
            .contentMargins(.top, 8, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .containerBackground(Color(.systemGroupedBackground), for: .navigation)
    }
}
