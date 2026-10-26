import SwiftUI

extension EnvironmentValues {
    /// True in the split layout, when the Duo is open.
    @Entry var isUnfolded = false
    /// True when pages put their buttons at the bottom (above the tab bar, or in the bottom bar
    /// with search's field) rather than the navigation bar: unfolded in portrait. In landscape or
    /// folded, the navigation bar's buttons are in a side rail.
    @Entry var usesBottomBar = true
    /// Unfolded, the list pane is white, so its rows are grey to stand out; nil keeps the default.
    @Entry var listRowFill: Color? = nil
}

extension View {
    /// Lines up with the list cards of a page beside the side rail: inset from the leading edge,
    /// and meeting the rail's inset on the trailing one, which already spaces them from the rail.
    func railPageMargins() -> some View {
        padding(.leading, 20)
    }
}
