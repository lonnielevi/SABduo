import SwiftUI

/// Where Queue and History's controls go: unfolded in portrait, in the tab bar's accessory
/// (`ListsAccessory`); in landscape, in the side rail (`ListsRailItems`), unfolded with search's.
private struct ListsToolbar: ViewModifier {
    @Environment(\.isUnfolded) private var isUnfolded
    @Environment(\.usesBottomBar) private var usesBottomBar

    func body(content: Content) -> some View {
        // The page picker or tab bar stands in for the title.
        let content = content.navigationBarTitleDisplayMode(.inline).toolbar(removing: .title)
        if usesBottomBar || isUnfolded {
            // In the tab bar's accessory, or the search pane's rail, which runs down the trailing pane.
            content
        } else {
            content.toolbar { ListsRailItems() }
        }
    }
}

/// The pages' controls above the tab bar, unfolded in portrait, like Music's player: clearing, plus
/// the queue's pause, speed limit and add; or Settings' lock and save.
struct ListsAccessory: View {
    @Environment(AppStore.self) private var store
    @Environment(\.rootActions) private var actions

    var body: some View {
        HStack(spacing: 4) {
            Group {
                switch store.listPane {
                case .queue:
                    ClearQueueButton()
                    GlobalControls()
                    Button("Add NZB", systemImage: "plus", action: actions.addNZB)
                        .disabled(!store.isConfigured)
                case .history:
                    HistoryClearButtons()
                case .settings:
                    if let controls = store.settingsControls { SettingsButtons(controls: controls) }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .tint(.primary)
        .padding(.horizontal, 8)
    }
}

/// The pages' controls in the side rail, in landscape or folded. Unfolded, the rail runs down the
/// trailing pane, so they go there beside its own, and stay while search fills the display: the
/// queue's still work then. Settings' don't, with its form slid away. Folded, Settings puts its
/// own in the rail.
struct ListsRailItems: ToolbarContent {
    @Environment(AppStore.self) private var store
    @Environment(\.rootActions) private var actions
    @Environment(\.usesBottomBar) private var usesBottomBar

    var body: some ToolbarContent {
        if !usesBottomBar, store.listPane == .settings, let controls = store.settingsControls,
           !store.searchFullScreen || store.selectedJobID != nil {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItemGroup(placement: .topBarTrailing) {
                SettingsButtons(controls: controls)
            }
        } else if !usesBottomBar, store.listPane != .settings {
            // Their own group, apart from the trailing pane's buttons above them.
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            if store.listPane == .queue {
                ToolbarItem(placement: .topBarTrailing) { ClearQueueButton() }
            } else {
                ToolbarItemGroup(placement: .topBarTrailing) { HistoryClearButtons() }
            }
            if store.listPane == .queue {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    GlobalControls()
                    Button("Add NZB", systemImage: "plus", action: actions.addNZB)
                        .disabled(!store.isConfigured)
                }
            }
        }
    }
}

extension View {
    func listsToolbar() -> some View {
        modifier(ListsToolbar())
    }
}

/// A page of the app, as the tab bars name it.
enum Page: Hashable {
    case search, queue, history, settings

    init(_ pane: ListPane) {
        switch pane {
        case .queue: self = .queue
        case .history: self = .history
        case .settings: self = .settings
        }
    }

    /// The leading pane's page this is, when unfolded; search has a pane of its own there.
    var listPane: ListPane? {
        switch self {
        case .search: nil
        case .queue: .queue
        case .history: .history
        case .settings: .settings
        }
    }

    var systemImage: String {
        switch self {
        case .search: "magnifyingglass"
        case .queue: "tray.and.arrow.down"
        case .history: "clock"
        case .settings: "gear"
        }
    }

    var title: String {
        switch self {
        case .search: "Search"
        case .queue: "Queue"
        case .history: "History"
        case .settings: "Settings"
        }
    }
}
