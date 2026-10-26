import SwiftUI

/// Unfolded: queue or history on the leading half; search, or the selected job, on the trailing half.
/// With search hidden, the trailing half is only for the selected job.
/// In portrait, and in book mode, the halves split the screen, putting the divider on the fold; the
/// side rail takes its room from the pane beside it. Otherwise in landscape they split the room
/// beside the rail, so the panes are the same usable width.
struct SplitLayout: View {
    @Environment(AppStore.self) private var store
    /// Partly open, held like a book.
    var isBook = false
    /// The side rail's inset, and the status bar's opposite it. Read outside the layout, which
    /// ignores them to run edge to edge.
    @State private var sideInsets = EdgeInsets()
    var body: some View {
        // A selected job always shows beside the list it came from.
        let searchFills = store.searchFullScreen && store.selectedJobID == nil && store.showsSearch
        GeometryReader { proxy in
            // The interface orientation, not the layout's shape: the keyboard shortens the layout,
            // and in portrait that can leave it wider than tall. Read whenever the size changes,
            // which every rotation does.
            let isLandscape = UIApplication.interfaceIsLandscape
            Group {
                if isLandscape {
                    // Around both panes, so the tab bar goes in the window's side rail; each tab
                    // shows its page beside search.
                    TabView(selection: pageSelection) {
                        ForEach(Self.pages, id: \.self) { page in
                            Tab(value: page) {
                                // The tab bar's rail narrows the tab and centres it. Lay the split
                                // out from the screen's leading edge instead, with the rail's
                                // inset on the pane beside it.
                                Color.clear.overlay(alignment: .leading) {
                                    split(width: proxy.size.width, insets: isBook ? EdgeInsets() : sideInsets, searchFills: searchFills) {
                                        landscapePage(page)
                                    }
                                }
                                // Its pages are hidden while search fills the screen.
                                .toolbarVisibility(searchFills ? .hidden : .visible, for: .tabBar)
                            } label: {
                                Image(systemName: page.systemImage)
                                    .accessibilityLabel(page.title)
                            }
                        }
                    }
                } else {
                    split(width: proxy.size.width, searchFills: searchFills) { tabs }
                }
            }
            // Opening out of book mode, or into it, slides the divider between the fold and the
            // middle of the room beside the rail.
            .animation(.smooth, value: isBook)
            .environment(\.isUnfolded, true)
            .environment(\.usesBottomBar, !isLandscape)
        }
        .ignoresSafeArea(.container, edges: .horizontal)
        .background {
            Color.clear.onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { sideInsets = $0 }
        }
        // End editing on rotation: each orientation lays the panes out afresh, and a keyboard
        // carried across can leave its space behind. Rotating always changes the size, which
        // re-reads the orientation here.
        .onGeometryChange(for: Bool.self) { _ in UIApplication.interfaceIsLandscape } action: { _ in
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    /// The two halves: the list pane's page and search, or search alone. Each takes half the room
    /// between the insets, plus the inset on its own outer edge; with none, they meet on the fold.
    private func split(width: CGFloat, insets: EdgeInsets = EdgeInsets(), searchFills: Bool, @ViewBuilder leading: () -> some View) -> some View {
        let half = (width - insets.leading - insets.trailing) / 2
        return HStack(spacing: 0) {
            if !searchFills {
                leading()
                    .frame(width: insets.leading + half)
                    .overlay(alignment: .trailing) { Divider().ignoresSafeArea() }
                    .transition(.move(edge: .leading))
            }
            Group {
                // While search fills the screen, they go with it instead.
                if searchFills { trailing.statusBanner() } else { trailing }
            }
            .frame(width: searchFills ? width : half + insets.trailing)
        }
    }

    /// Landscape: a page under the stats, level with search's indexer. Its buttons are in the side
    /// rail, below search's, and the tabs at its foot.
    private func landscapePage(_ page: Page) -> some View {
        NavigationStack {
            self.page(page.listPane ?? .queue)
                .containerBackground(Color(.systemBackground), for: .navigation)
                // The app's errors and notices are about the server, so they go with its pages;
                // inside the rail's inset being ignored below, so they span the pane like the stats.
                .statusBanner()
                .safeAreaBar(edge: .top) {
                    // Below the gap the search pane's folded-away bar leaves.
                    stats.padding(.top, 32)
                }
                // The tab bar's rail insets the whole tab, but it's beside search's half, not this one.
                .ignoresSafeArea(.container, edges: .trailing)
                .contentMargins(.top, 8, for: .scrollContent)
                // The search pane's empty bar folds away; this one would stay as a blank row
                // above the stats, so hide it and the two line up.
                .toolbarVisibility(.hidden, for: .navigationBar)
        }
    }

    /// Portrait: the pages in the system tab bar, at the bottom of this pane as on an iPhone, with
    /// the page's buttons in its accessory above. The stats sit level with the status bar.
    private var tabs: some View {
        TabView(selection: pageSelection) {
            ForEach(Self.pages, id: \.self) { page in
                Tab(value: page) {
                    NavigationStack {
                        self.page(page.listPane ?? .queue)
                            .containerBackground(Color(.systemBackground), for: .navigation)
                            // In a bar inside the page, raised level with the status bar. Floating
                            // over the tab view instead stops search's stack beside it from pushing.
                            .safeAreaBar(edge: .top) {
                                stats.padding(.top, UIApplication.statusBarMidY - QueueStatsCard.height / 2 - UIApplication.windowTopInset)
                            }
                            .contentMargins(.top, 8, for: .scrollContent)
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
        // The page's buttons, above the tab bar like Music's player.
        .tabViewBottomAccessory { ListsAccessory() }
        // The pane is iPhone-wide; a regular width would put the tabs at the top, iPad-style.
        .environment(\.horizontalSizeClass, .compact)
    }

    private func page(_ pane: ListPane) -> some View {
        Group {
            switch pane {
            case .queue: QueueView(highlightsSelection: true)
            case .history: HistoryView()
            case .settings:
                ServerSettingsView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(removing: .title)
            }
        }
        // White, apart from search's grey, with grey cards to stand out on it.
        .scrollContentBackground(.hidden)
        .environment(\.listRowFill, Color(.secondarySystemBackground))
    }

    private static let pages: [Page] = [.queue, .history, .settings]

    private var pageSelection: Binding<Page> {
        Binding(
            get: { Page(store.listPane) },
            set: { page in
                let pane = page.listPane ?? .queue
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

    /// The download stats, on every page of the list pane. The tab bars have no room for the
    /// server's light beside Queue, so they carry it.
    private var stats: some View {
        QueueStatsCard(showsServerLight: true)
            .padding(.horizontal)
    }

    private var trailing: some View {
        Group {
            if let id = store.selectedJobID {
                NavigationStack {
                    JobDetailView(jobID: id)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                if store.showsSearch {
                                    Button("Search", systemImage: "magnifyingglass") {
                                        store.selectedJobID = nil
                                    }
                                } else {
                                    Button("Close", systemImage: "xmark") {
                                        store.selectedJobID = nil
                                    }
                                }
                            }
                            ListsRailItems()
                        }
                        .id(id)
                }
            } else if store.showsSearch {
                SearchStack()
            } else {
                // With search hidden, this half is for a job's details.
                NavigationStack {
                    ContentUnavailableView("No Job Selected", systemImage: "tray",
                                           description: Text("Select a job in the queue to see its details."))
                        .emptyStatePlacement()
                        .toolbar { ListsRailItems() }
                }
            }
        }
    }
}

