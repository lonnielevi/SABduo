import SwiftUI

/// Navigation for search, shared by the Search page (folded) and the trailing pane (unfolded).
/// The path lives in `SearchModel`, so the current screen survives a fold/unfold.
struct SearchStack<Header: View>: View {
    @Environment(AppStore.self) private var store
    @Environment(\.isUnfolded) private var isUnfolded
    @Environment(\.usesBottomBar) private var usesBottomBar
    /// Folded, the download stats, pinned above each search page and its search field.
    @ViewBuilder var header: Header
    /// How far the side rail insets the pages. Unfolded it insets the navigation but not what
    /// floats over it, so the field takes the inset from here.
    @State private var pageInset: CGFloat = 0

    var body: some View {
        // Outside the navigation, so it stays put as the page scrolls, with the page's search
        // field beneath it. On every search page: added and removed, it resized the navigation
        // mid-slide, and going back jumped.
        VStack(spacing: 0) {
            if Header.self != EmptyView.self {
                header
                    // Level with the other pages' stats, which sit beneath their empty navigation bar,
                    // and the field beneath level with their first card.
                    .padding(.top, 24)
                    .padding(.bottom, -2)
            }
            navigation
        }
        // Unfolded in portrait, with no rail, expand floats at the foot of the pane, centred, as
        // tall as the tab bar beside it and level with it. In the navigation bar, a Live Activity
        // that pushes the status bar into the pane's row makes iOS fold it into an overflow menu.
        .overlay(alignment: .bottom) {
            if usesBottomBar {
                SearchFullScreenButton()
                    .labelStyle(.iconOnly)
                    // A touch under the tab bar's icons: corner to corner, the arrows look larger.
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 62, height: 62)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .padding(.bottom, 21)
                    .ignoresSafeArea(edges: .bottom)
            }
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

/// The system's search field, across the top of each search page and always showing, as in
/// Apple Music. Trying it in place of `SearchPill`.
private struct NativeSearch: ViewModifier {
    @Environment(AppStore.self) private var store

    func body(content: Content) -> some View {
        @Bindable var search = store.search
        let feed = store.search.activeFeed
        @Bindable var bindableFeed = feed
        let client = store.newznabClient(for: store.activeIndexer)
        content
            .searchable(
                text: $bindableFeed.query,
                isPresented: $search.fieldOpen,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: store.searchPrompt(for: feed)
            )
            .onSubmit(of: .search) { store.search.submit(feed, using: client) }
    }
}

/// Unfolded, each search page takes the pane's own background, so it stands apart from the list
/// pane beside it.
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

/// Search's buttons in the navigation bar: back from results on the home screen, and unfolded,
/// expand: at the top in portrait, in the side rail in landscape with the queue's below.
private struct SearchButtons: ToolbarContent {
    @Environment(AppStore.self) private var store
    @Environment(\.isUnfolded) private var isUnfolded
    @Environment(\.usesBottomBar) private var usesBottomBar

    var body: some ToolbarContent {
        // Results on the home screen, from a favorite or a search of everything, have no page to
        // go back from, so they get a back button of their own.
        if store.search.path.isEmpty, !store.search.isHome {
            ToolbarItem(placement: .topBarLeading) { SearchResultsBackButton() }
        }
        // The side rail, unfolded in landscape.
        if isUnfolded, !usesBottomBar {
            ToolbarItem(placement: .topBarTrailing) { SearchFullScreenButton() }
            ListsRailItems()
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
private struct SearchScreenTitle: ViewModifier {
    let title: String
    let subtitle: String
    /// The home screen, which goes untitled.
    let prominent: Bool

    func body(content: Content) -> some View {
        let content = content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            // The header already separates the list from the buttons; drop the list's own top gap.
            .contentMargins(.top, 8, for: .scrollContent)
        // No bar at all rather than an empty one, which would push the page down.
        if prominent {
            content
        } else {
            content.safeAreaBar(edge: .top) {
                PaneTitle(title: title, subtitle: subtitle)
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

extension View {
    func searchScreenTitle(_ title: String, subtitle: String = "", prominent: Bool = false) -> some View {
        modifier(SearchScreenTitle(title: title, subtitle: subtitle, prominent: prominent))
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

/// Unfolded: widens search over the queue/history side, or puts the split back.
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
