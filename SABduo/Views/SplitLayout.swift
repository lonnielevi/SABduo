import SwiftUI

/// Unfolded: search on the leading half; queue or history on the trailing half, where a selected
/// job opens over the queue. With search hidden, the leading half is for the selected job instead.
/// In portrait, and in book mode, the halves split the screen, putting the divider on the fold; the
/// side rail takes its room from the pane beside it. Otherwise in landscape they split the room
/// beside the rail, so the panes are the same usable width.
struct SplitLayout: View {
    @Environment(AppStore.self) private var store
    /// Partly open, held like a book.
    var isBook = false
    /// The interface orientation, not the layout's shape: the keyboard shortens the layout, and in
    /// portrait that can leave it wider than tall.
    var isLandscape = false
    /// The width to lay out in, edge to edge across the side rail and the status bar.
    var width: CGFloat = 0
    /// The side rail's inset, and the status bar's opposite it, which the layout ignores to run
    /// edge to edge.
    var sideInsets = EdgeInsets()
    /// The window's top safe area inset, given rather than asked of the window: asking it while
    /// laying out makes the layout depend on itself, and then it misses rotations.
    var topInset: CGFloat = 0
    var body: some View {
        // A job opens over the queue, which stays beneath search.
        let searchFills = store.searchFullScreen && store.showsSearch
        Group {
            if isLandscape {
                let insets = isBook ? EdgeInsets() : sideInsets
                // Around both panes, so the tab bar goes in the window's side rail; each tab
                // shows its page, leaving room for search.
                TabView(selection: pageSelection) {
                    ForEach(Self.pages, id: \.self) { page in
                        Tab(value: page) {
                            // The tab bar's rail narrows the tab and centres it. Lay the split
                            // out from the screen's leading edge instead, with the rail's
                            // inset on the pane beside it.
                            Color.clear.overlay(alignment: .leading) {
                                split(width: width, insets: insets, searchFills: false, holdsSearch: false) {
                                    landscapePage(page)
                                }
                            }
                        } label: {
                            Image(systemName: page.systemImage)
                                .accessibilityLabel(page.title)
                        }
                    }
                }
                // One search for every tab, over the room they leave it, so switching tabs
                // doesn't swap it, nor its field's button in the rail.
                .overlay(alignment: .leading) {
                    searchColumn(width: width, insets: insets, searchFills: false)
                }
            } else {
                split(width: width, searchFills: searchFills) { tabs }
            }
        }
        // Built afresh for each orientation: otherwise search's pane can keep the width it had
        // in the last, whatever it's given in this one. What's open lives in the store.
        .id(isLandscape)
        // Opening out of book mode, or into it, slides the divider between the fold and the
        // middle of the room beside the rail.
        .animation(.smooth, value: isBook)
        .environment(\.isUnfolded, true)
        .environment(\.usesBottomBar, !isLandscape)
        .ignoresSafeArea(.container, edges: .horizontal)
        // End editing on rotation: each orientation lays the panes out afresh, and a keyboard
        // carried across can leave its space behind.
        .onChange(of: isLandscape) {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    /// The two halves: search and the list pane's page. Each takes half the room between the
    /// insets, plus the inset on its own outer edge; with none, they meet on the fold.
    ///
    /// For search to fill the screen, the list pane slides off the trailing edge as search widens
    /// into its room, like an iPad sidebar hiding. It stays laid out while it's away, so it comes
    /// back as it was.
    private func split(width: CGFloat, insets: EdgeInsets = EdgeInsets(), searchFills: Bool, holdsSearch: Bool = true, @ViewBuilder lists: () -> some View) -> some View {
        let half = (width - insets.leading - insets.trailing) / 2
        return HStack(spacing: 0) {
            if holdsSearch {
                searchColumn(width: width, insets: insets, searchFills: searchFills)
            } else {
                Color.clear
                    .frame(width: insets.leading + half)
                    .allowsHitTesting(false)
            }
            lists()
                .frame(width: half + insets.trailing)
                .overlay(alignment: .leading) { Divider().ignoresSafeArea() }
                .accessibilityHidden(searchFills)
                .allowsHitTesting(!searchFills)
        }
        .frame(width: width, alignment: .leading)
    }

    /// Search's half, headed by the stats; the whole width while it fills the screen.
    private func searchColumn(width: CGFloat, insets: EdgeInsets, searchFills: Bool) -> some View {
        let half = (width - insets.leading - insets.trailing) / 2
        let topInset = topInset + 4
        // Lower the stats, and the pane with them, to line the title up with the status bar's
        // clock: in landscape, beside them, the tops; in portrait, over the list pane, the middles.
        let drop: CGFloat = isLandscape ? 12 : 13
        // The stats head this half, near the top: the status bar is over the other.
        //
        // Search's field is at the foot and its bar hidden, and a job's page has buttons there,
        // so the pages start beneath them. Not part way: a bar that starts within the top inset
        // still keeps clear of all of it.
        let pagesTop = max(topInset, Self.statsBottom) + drop
        return Group {
            if store.showsSearch {
                // In a bar, so the pages scroll beneath the stats, as the list pane's do.
                SearchStack(headerTop: 14 + drop, pagesTop: pagesTop) { stats }
                    .ignoresSafeArea(.container, edges: .top)
            } else {
                searchPane
                    .ignoresSafeArea(.container, edges: .top)
                    .padding(.top, pagesTop)
                    .ignoresSafeArea(.container, edges: .top)
                    .overlay(alignment: .top) {
                        stats
                            .padding(.top, 14 + drop)
                            .ignoresSafeArea(.container, edges: .top)
                    }
            }
        }
        .background {
            (store.showsSearch ? Color.searchPane : Color(.systemGroupedBackground))
                .ignoresSafeArea()
        }
        // While search fills the screen, the app's notices go with it.
        .statusBanner(searchFills)
        .frame(width: searchFills ? width : insets.leading + half)
    }

    /// Landscape: a page, beside the side rail, with its buttons in the rail and the tabs at its
    /// foot. Search keeps its half: there's no expand in landscape.
    private func landscapePage(_ page: Page) -> some View {
        NavigationStack(path: jobPath(page)) {
            self.page(page.listPane ?? .queue)
                .containerBackground(Color(.systemBackground), for: .navigation)
                // The app's errors and notices are about the server, so they go with its pages.
                .statusBanner()
                .toolbar {
                    SearchRailBackItem()
                    ListsRailItems()
                }
        }
        // The first card's top level with the title's and the clock's, on the list and on a job
        // opened over it.
        .contentMargins(.top, 10, for: .scrollContent)
        // The cards end at the rail's safe area, which its buttons overhang: as far from them
        // as from the divider.
        .environment(\.railGap, 8)
    }

    /// Portrait: the pages in the system tab bar, at the bottom of this pane as on an iPhone, with
    /// the page's buttons in its accessory above.
    private var tabs: some View {
        TabView(selection: pageSelection) {
            ForEach(Self.pages, id: \.self) { page in
                Tab(value: page) {
                    NavigationStack(path: jobPath(page)) {
                        self.page(page.listPane ?? .queue)
                            .containerBackground(Color(.systemBackground), for: .navigation)
                            // Lower, so the first card is level with search's beside it, beneath
                            // the stats.
                            .contentMargins(.top, 25, for: .scrollContent)
                            // The app's errors and notices are about the server, so they go with
                            // its pages, inside the page so they sit above the tab bar.
                            .statusBanner()
                    }
                } label: {
                    // Icons alone, which the pages' buttons above share.
                    Image(systemName: page.systemImage)
                        .accessibilityLabel(page.title)
                }
            }
        }
        // The page's buttons, above the tab bar like Music's player. They're for the list, so an
        // open job, with back alone, goes without them.
        .tabViewBottomAccessory(isEnabled: !jobOpen) { ListsAccessory() }
        // The pane is iPhone-wide; a regular width would put the tabs at the top, iPad-style.
        .environment(\.horizontalSizeClass, .compact)
    }

    private func page(_ pane: ListPane) -> some View {
        Group {
            switch pane {
            case .queue: QueueView(highlightsSelection: true).railGap()
            case .history: HistoryView().railGap()
            case .settings:
                ServerSettingsView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(removing: .title)
            }
        }
        // White, apart from search's grey, with grey cards to stand out on it.
        .scrollContentBackground(.hidden)
        .environment(\.listRowFill, Color(.secondarySystemBackground))
        .navigationDestination(for: QueueSlot.ID.self) { id in
            JobDetailView(jobID: id)
                .railGap()
        }
    }

    /// The queue's path mirrors `selectedJobID`, so a job opens over it. With search hidden, the
    /// job has the other half to itself instead.
    private func jobPath(_ page: Page) -> Binding<[QueueSlot.ID]> {
        Binding(
            get: {
                guard page == .queue, store.showsSearch else { return [] }
                return store.selectedJobID.map { [$0] } ?? []
            },
            set: { path in
                if page == .queue, store.showsSearch { store.selectedJobID = path.last }
            }
        )
    }

    private static let pages: [Page] = [.queue, .history, .settings]

    /// A job open over the queue, or a history item over the history, on screen.
    private var jobOpen: Bool {
        switch store.listPane {
        case .queue: store.showsSearch && store.selectedJobID != nil
        case .history: store.selectedHistoryID != nil
        case .settings: false
        }
    }

    /// Below the stats at the top of search's half: 14pt down, the speed, and the line beneath.
    private static let statsBottom: CGFloat = 86

    private var pageSelection: Binding<Page> {
        Binding(
            get: { Page(store.listPane) },
            set: { page in
                let pane = page.listPane ?? .queue
                // A page from the rail while search fills the screen brings the list pane back.
                if store.searchFullScreen {
                    withAnimation(.smooth) { store.searchFullScreen = false }
                }
                // In landscape the page's buttons join the side rail, where an animation would slide
                // them in from off the screen; the tab view swaps the page itself without one.
                if UIApplication.interfaceIsLandscape {
                    store.listPane = pane
                } else {
                    withAnimation(.snappy) { store.listPane = pane }
                }
            }
        )
    }

    /// The download stats, above search or a job. The tab bars have no room for the server's
    /// light beside Queue, so they carry it.
    private var stats: some View {
        QueueStatsCard(showsServerLight: true)
            .padding(.horizontal)
    }

    private var searchPane: some View {
        Group {
            if let id = store.selectedJobID {
                NavigationStack {
                    JobDetailView(jobID: id)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Close", systemImage: "xmark") {
                                    store.selectedJobID = nil
                                }
                            }
                        }
                        .id(id)
                }
            } else {
                // With search hidden, this half is for a job's details.
                NavigationStack {
                    ContentUnavailableView("No Job Selected", systemImage: "tray",
                                           description: Text("Select a job in the queue to see its details."))
                        .emptyStatePlacement()
                }
            }
        }
    }
}

