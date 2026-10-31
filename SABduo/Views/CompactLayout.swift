import SwiftUI

/// Folded: one page at a time, picked from the tab bar, which the cover display puts in the side rail: Search,
/// Queue, History and Settings. A job opens over the queue.
struct CompactLayout: View {
    @Environment(AppStore.self) private var store
    @State private var page: Page = .search
    /// A page picked from the tab bar, or for a button elsewhere, since folding.
    @State private var picked = false

    var body: some View {
        TabView(selection: Binding(get: { page }, set: show)) {
            // A plain tab at the top of the rail, as in Apple Music's sidebar, rather than the search
            // role's tab apart at the end. Its field is a button in the rail, above the tabs.
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
            // History or Settings if the list pane was showing one, then the queue if it has a
            // job or one is open, then search.
            if store.listPane != .queue {
                page = Page(store.listPane)
            } else if store.selectedJobID != nil || !store.slots.isEmpty || !store.showsSearch {
                page = .queue
            } else {
                page = .search
            }
        }
        // Launched folded, the queue arrives after the page is picked; if it has jobs, go to it,
        // unless another page has been picked since.
        .onChange(of: store.queue == nil) {
            if !picked, page == .search, !store.slots.isEmpty { page = .queue }
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
            // Up into the empty navigation bar's row, so the title's top is as far from the
            // screen's top as its first letter is from the side.
            .padding(.top, -7.33)
            .padding(.bottom, 4)
    }

    private func show(_ new: Page) {
        page = new
        picked = true
        // Also the page to land on when unfolding. Search has its own half there, so beside it
        // the queue, which also brings search back on folding again rather than History or Settings.
        store.listPane = new.listPane ?? .queue
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
