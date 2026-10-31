import SwiftUI

/// Navigation for search, shared by the Search page (folded) and the leading pane (unfolded).
/// The path lives in `SearchModel`, so the current screen survives a fold/unfold.
struct SearchStack<Header: View>: View {
    @Environment(AppStore.self) private var store
    @Environment(\.usesBottomBar) private var usesBottomBar
    /// Where the header starts beneath the top of the stack.
    var headerTop: CGFloat = 24
    /// Where the pages start, if not beneath the header and the navigation bar's empty row.
    var pagesTop: CGFloat?
    /// The download stats, pinned above each search page and its search field.
    @ViewBuilder var header: Header
    /// How far the side rail insets the pages. Unfolded it insets the navigation but not what
    /// floats over it, so the field takes the inset from here.
    @State private var pageInset: CGFloat = 0
    /// The header's height: the navigation doesn't pass the bar's room on to its pages.
    @State private var headerHeight: CGFloat = 0
    /// Where the pages start beneath the header: 14pt up into it, where the navigation bar's
    /// empty row leaves the first card level with the other pages'.
    private var pageTop: CGFloat { pagesTop ?? max(headerHeight - 14, 0) }
    /// The home page's top: folded, without a trail beneath the stats, it starts higher.
    private var homeTop: CGFloat { pagesTop ?? max(pageTop - 8, 0) }

    var body: some View {
        // Over the navigation rather than on each page, so it stays put as pages slide: added
        // and removed with them, it resized the navigation mid-slide, and going back jumped. A
        // bar, so the page scrolls beneath it, as on the other pages.
        if Header.self != EmptyView.self {
            navigation.safeAreaBar(edge: .top) {
                header
                    // Level with the other pages' stats, which sit beneath their empty navigation bar.
                    .padding(.top, headerTop)
                    .padding(.bottom, -2)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            }
        } else {
            navigation
        }
    }

    private var navigation: some View {
        NavigationStack(path: Bindable(store.search).path) {
            home
                // Read from the home screen even while it's pushed aside: the inset doesn't move.
                .background {
                    Color.clear
                        .ignoresSafeArea()
                        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.trailing } action: { pageInset = $0 }
                }
                .toolbar { SearchButtons() }
                .modifier(NativeSearch())
                .modifier(SearchPaneBackground())
                .modifier(SteadyRailInset())
                // Without a trail beneath the stats, the picker up level with the other pages'
                // first card.
                .modifier(PageTop(top: homeTop, replacesInset: pagesTop != nil))
                .navigationDestination(for: SearchRoute.self) { route in
                    Group {
                        switch route {
                        case .category(let category): CategoryView(category: category)
                        case .browse(let category): BrowseView(category: category)
                        case .release(let result): ReleaseDetailView(result: result)
                        }
                    }
                    .toolbar { SearchButtons() }
                    .modifier(NativeSearch())
                    .modifier(SearchPaneBackground())
                    .modifier(SteadyRailInset())
                    .modifier(PageTop(top: pageTop, replacesInset: pagesTop != nil))
                }
        }
    }

    private var home: some View {
        SearchView()
    }
}

extension SearchStack where Header == EmptyView {
    init() { header = EmptyView() }
}

/// Room at the top of a search page, beneath the header. Given where the pages start, it's in
/// place of the window's top inset, which the pages still get from the navigation in portrait.
private struct PageTop: ViewModifier {
    var top: CGFloat
    var replacesInset: Bool

    func body(content: Content) -> some View {
        if replacesInset {
            content
                .safeAreaPadding(.top, top)
                .ignoresSafeArea(.container, edges: .top)
        } else {
            content.safeAreaPadding(.top, top)
        }
    }
}

/// The system's search field, always showing, in the bottom bar as in Apple Music, leaving the
/// top to the stats.
private struct NativeSearch: ViewModifier {
    @Environment(AppStore.self) private var store
    @Environment(\.isUnfolded) private var isUnfolded

    func body(content: Content) -> some View {
        @Bindable var search = store.search
        let feed = store.search.activeFeed
        @Bindable var bindableFeed = feed
        let client = store.newznabClient(for: store.activeIndexer)
        content
            .searchable(
                text: $bindableFeed.query,
                isPresented: $search.fieldOpen,
                placement: .toolbar,
                prompt: store.searchPrompt(for: feed)
            )
            // Unfolded, the bar at the top is empty: the stats and the trail of pages are above
            // the page instead, and the edge swipe goes back. Folded, it keeps the back button.
            .toolbarVisibility(isUnfolded ? .hidden : .automatic, for: .navigationBar)
            // Typing keeps the bar's row, so the field stays put rather than rising under the stats.
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .onSubmit(of: .search) { store.search.submit(feed, using: client) }
    }
}

/// Unfolded, each search page takes the pane's own background, so it stands apart from the list
/// pane beside it.
/// Folded, the page keeps the side rail's room as a margin of its own rather than the rail's
/// safe area: the field's ✕ hides the rail and brings it back, and on the way the safe area
/// drops for a moment, which widens the rows and narrows them again.
private struct SteadyRailInset: ViewModifier {
    @Environment(\.isUnfolded) private var isUnfolded
    /// The rail's inset, the narrowest reported: closing search briefly reports twice it.
    @State private var inset: CGFloat = 0

    func body(content: Content) -> some View {
        // Unfolded, the rail isn't beside search, and a margin of none would put the rows against
        // the divider.
        if isUnfolded {
            content
        } else {
            steady(content)
        }
    }

    private func steady(_ content: Content) -> some View {
        content
            .contentMargins(.trailing, inset, for: .scrollContent)
            .ignoresSafeArea(.container, edges: .trailing)
            .background {
                Color.clear
                    .ignoresSafeArea()
                    .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.trailing } action: { reported in
                        if reported > 0, inset == 0 || reported < inset { inset = reported }
                    }
            }
    }
}

private struct SearchPaneBackground: ViewModifier {
    @Environment(\.isUnfolded) private var isUnfolded

    func body(content: Content) -> some View {
        if isUnfolded {
            content
                .scrollContentBackground(.hidden)
                .containerBackground(Color.searchPane, for: .navigation)
        } else {
            content
        }
    }
}

private extension AppStore {
    func searchPrompt(for feed: ResultFeed) -> String {
        if let category = feed.category { return "Search \(category.name)" }
        return activeIndexer.map { "Search \($0.name)" } ?? "Search"
    }
}

/// Search's buttons in the navigation bar: back from results on the home screen, folded.
private struct SearchButtons: ToolbarContent {
    @Environment(AppStore.self) private var store
    @Environment(\.isUnfolded) private var isUnfolded
    @Environment(\.usesBottomBar) private var usesBottomBar

    var body: some ToolbarContent {
        // Results on the home screen, from a favorite or a search of everything, have no page to
        // go back from, so they get a back button of their own. Unfolded, the trail of pages
        // stands in for it (see `SearchScreenTitle`).
        if store.search.path.isEmpty, !store.search.isHome, !isUnfolded {
            ToolbarItem(placement: .topBarLeading) { SearchResultsBackButton() }
        }
        // The field is in the bottom bar; unfolded in portrait, between back and expand, level
        // with the tab bar. Back only off the home page.
        if isUnfolded, usesBottomBar, !store.search.isHome {
            ToolbarItem(placement: .bottomBar) { SearchBackButton() }
            ToolbarSpacer(.fixed, placement: .bottomBar)
        }
        DefaultToolbarItem(kind: .search, placement: .bottomBar)
        if isUnfolded {
            if usesBottomBar {
                ToolbarSpacer(.fixed, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) { SearchFullScreenButton() }
            }
        }
    }
}

/// A search field floating over the bottom of the search pages: lined up with the page's cards,
/// and level with the foot of the tab bar, which sits nearer the bottom edge than the safe area.
/// Tapping into it opens it.
private struct SearchPill: View {
    @Environment(AppStore.self) private var store
    /// How far the side rail insets the page; the field matches it.
    let pageInset: CGFloat
    @FocusState private var fieldFocused: Bool
    /// Where the keyboard's top edge is, in screen coordinates; infinite while it's away.
    @State private var keyboardTop = CGFloat.infinity
    /// The bottom of the space the pill sits in, and how far its own safe area is inset already.
    @State private var spaceBottom: CGFloat = 0
    @State private var spaceInset: CGFloat = 0

    var body: some View {
        let feed = store.search.activeFeed
        let client = store.newznabClient(for: store.activeIndexer)

        let isSearching = store.search.fieldOpen
        field(feed: feed, client: client)
            .onChange(of: isSearching, initial: true) { fieldFocused = isSearching }
            .onChange(of: fieldFocused) { store.search.fieldOpen = fieldFocused }
            // Beside a rail, the page's cards meet its inset; without one, they're inset alike, and
            // the tab bar on the other half sits a little lower.
            .padding(.leading, pageInset > 0 ? 20 : 16)
            .padding(.trailing, pageInset > 0 ? max(pageInset - spaceInset, 0) : 16)
        // Rise with the keyboard only for this field, to just above it. The layouts ignore the
        // keyboard (see `RootView`), so measure it instead. Beside a side rail the tab view
        // shortens the page to the keyboard's top itself, leaving nothing to rise by but the gap.
        .padding(.bottom, isSearching && keyboardTop.isFinite ? max(spaceBottom - keyboardTop, 0) + 8 : pageInset > 0 ? -7.67 : -13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { spaceBottom = $0 }
        .background {
            Color.clear
                .ignoresSafeArea()
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.trailing } action: { spaceInset = $0 }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            withAnimation(.smooth) { keyboardTop = frame.minY }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.smooth) { keyboardTop = .infinity }
        }
    }

    private func field(feed: ResultFeed, client: NewznabClient?) -> some View {
        @Bindable var feed = feed
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(store.searchPrompt(for: feed), text: $feed.query)
                .focused($fieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit {
                    store.search.submit(feed, using: client)
                    fieldFocused = false
                }
            if !feed.query.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { feed.query = "" }
                    .foregroundStyle(.secondary)
            }
            if store.search.fieldOpen {
                Button("Close Search", systemImage: "chevron.down") { close() }
                    .tint(.primary)
                    .frame(minWidth: 32, minHeight: 44)
            }
        }
        .labelStyle(.iconOnly)
        .padding(.leading, 16)
        .padding(.trailing, 8)
        // As tall as what it lines up with: the rail's selected tab beside a rail, or the tab bar
        // on the other half.
        .frame(minHeight: pageInset > 0 ? 57 : 62)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func close() {
        fieldFocused = false
        withAnimation(.smooth) { store.search.fieldOpen = false }
    }
}

/// Title and path for search screens, on a line of their own below the back button. A large
/// title would sit flush against the unfolded divider, so it's a padded header instead. The bar
/// keeps only buttons, so when it has none, it collapses and the header rises to the top.
/// The home screen shows no title: the tab bar or the pane already says it's search.
///
/// Unfolded, the stats sit where the bar's row would be, so in place of the title and the back
/// button there's a trail of the pages to here, each one a tap away, and the row stays empty
/// beneath the stats (see `SplitLayout`). It also heads a release, and results on the home screen.
private struct SearchScreenTitle: ViewModifier {
    @Environment(AppStore.self) private var store
    @Environment(\.isUnfolded) private var isUnfolded
    let title: String
    let subtitle: String
    /// The home screen, which goes untitled.
    let prominent: Bool

    func body(content: Content) -> some View {
        let titled = !prominent && !title.isEmpty
        let content = content
            .navigationBarBackButtonHidden(isUnfolded)
            .modifier(TitleStyle(title: title, applies: titled || prominent))
        // No bar at all rather than an empty one, which would push the page down.
        // Folded too, beneath the back button. The home screen only for results of its own: with
        // a page over it, the bar would show on it as it comes back into view.
        let feed = store.search.homeFeed
        if !prominent || feed.hasLoaded || feed.isLoading {
            content.safeAreaBar(edge: .top) {
                SearchTrail()
                    // Folded, up beneath the stats, as a line of them. Room beneath it, where the
                    // page scrolls in under the bar.
                    .padding(.top, isUnfolded ? 0 : -10)
                    .padding(.bottom, 6)
                    // Its left edge on the title's: the title's large S sits in from its own.
                    .padding(.leading, isUnfolded ? 0 : 3.33)
            }
        } else if titled {
            content.safeAreaBar(edge: .top) {
                PaneTitle(title: title, subtitle: subtitle)
            }
        } else {
            content
        }
    }

    private struct TitleStyle: ViewModifier {
        let title: String
        let applies: Bool

        func body(content: Content) -> some View {
            if applies {
                content
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(removing: .title)
                    // The header already separates the list from the buttons; drop the list's own top gap.
                    .contentMargins(.top, 8, for: .scrollContent)
            } else {
                content
            }
        }
    }
}

/// A pane's title, drawn in a bar of its own when unfolded, so the list scrolls beneath it
/// and the titles of both panes sit at the same height.
struct PaneTitle: View {
    let title: String
    var subtitle = ""
    /// Top-level screens (Queue, History, Search) are large; deeper ones are smaller.
    var prominent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(prominent ? .largeTitle.bold() : .title2.bold())
            if !subtitle.isEmpty {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .padding(.horizontal)
        .padding(.horizontal, 4)
    }
}

/// The pages to this one: "Home › Movies › All Movies". Each before the last goes back to it.
private struct SearchTrail: View {
    @Environment(AppStore.self) private var store
    /// The path as this page opened, so the trail stays put while another page slides over it.
    @State private var opened: [SearchRoute]?

    var body: some View {
        let path = opened ?? store.search.path
        let names = Self.names(for: path)
        HStack(spacing: 6) {
            ForEach(names.indices, id: \.self) { index in
                if index > 0 {
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                if index == names.count - 1 {
                    Text(names[index])
                        .bold()
                        .layoutPriority(1)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    Button(names[index]) { go(to: index, in: path) }
                }
            }
        }
        .font(.title3)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.horizontal, 4)
        .onAppear { if opened == nil { opened = store.search.path } }
    }

    /// Home, then a name for each page: a category, all of it, one of its subcategories, a release.
    /// With no pages, the results of a search from the home screen.
    private static func names(for path: [SearchRoute]) -> [String] {
        guard !path.isEmpty else { return ["Home", "Results"] }
        var names = ["Home"]
        for (index, route) in path.enumerated() {
            switch route {
            case .category(let category):
                names.append(category.name)
            case .browse(let category):
                if index > 0, case .category(let parent) = path[index - 1], parent.id == category?.id {
                    names.append("All \(parent.name)")
                } else {
                    names.append(category?.name ?? "Latest Releases")
                }
            case .release:
                names.append("Release")
            }
        }
        return names
    }

    /// Back to the page at `index` in the trail; the first is home.
    private func go(to index: Int, in path: [SearchRoute]) {
        if index == 0 {
            withAnimation { store.search.goHome() }
        } else {
            store.search.path = Array(path.prefix(index))
        }
    }
}

extension View {
    func searchScreenTitle(_ title: String, subtitle: String = "", prominent: Bool = false) -> some View {
        modifier(SearchScreenTitle(title: title, subtitle: subtitle, prominent: prominent))
    }
}

/// Search's back, unfolded in landscape, at the top of the side rail above the list pane's
/// controls: search's own pane has no bar of its own there, only the trail.
struct SearchRailBackItem: ToolbarContent {
    @Environment(AppStore.self) private var store

    var body: some ToolbarContent {
        if store.showsSearch, !store.search.isHome {
            ToolbarItem(placement: .topBarTrailing) { SearchBackButton() }
        }
    }
}

/// Back a page of search; from results on the home page, to its categories.
private struct SearchBackButton: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Button("Back", systemImage: "chevron.backward") {
            if store.search.path.isEmpty {
                withAnimation { store.search.goHome() }
            } else {
                store.search.path.removeLast()
            }
        }
    }
}

/// Back from results on the home screen to its categories, clearing the search.
private struct SearchResultsBackButton: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Button("Back", systemImage: "chevron.backward") {
            withAnimation { store.search.goHome() }
        }
    }
}

/// Unfolded in portrait: widens search over the queue/history side, or puts the split back.
struct SearchFullScreenButton: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let isFull = store.searchFullScreen
        Button(isFull ? "Show Queue and History" : "Full Screen Search",
               systemImage: isFull ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
            // The list pane slides away as search widens, and back (see `SplitLayout`).
            withAnimation(.smooth) { store.searchFullScreen.toggle() }
        }
    }
}

/// Hiding a page's back button, to put one beside its title, also stops the swipe back from the
/// edge; let it start whenever there's a page to go back to.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

