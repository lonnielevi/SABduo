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

extension View {
    /// An empty pane's message, its top at a fixed height on the screen rather than centred in its
    /// pane, so messages side by side line up whatever their length or the bars above them.
    func emptyStatePlacement() -> some View {
        modifier(EmptyStatePlacement())
    }
}

private struct EmptyStatePlacement: ViewModifier {
    /// Where the top of the message goes, as a share of the window's height.
    private static let height: CGFloat = 0.3
    @State private var inset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Read again whenever the pane moves or resizes, which every rotation and fold does.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                inset = max(UIApplication.windowHeight * Self.height - frame.minY, 0)
            }
    }
}

extension Color {
    /// Search's pane unfolded, set apart from the list pane beside it: grouped grey in light mode,
    /// as there, and in dark mode a lifted black, still darker than its cards.
    static let searchPane = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.07, alpha: 1) : .systemGroupedBackground
    })
}
