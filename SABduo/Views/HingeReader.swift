import SwiftUI

/// Hinge state as the layout cares about it. `nil` means the device has no hinge
/// (or is on iOS 27.0, before `onHingeChange` existed).
enum HingeState: Equatable {
    case closed
    case open
}

/// iPhone Duo reports hinge changes through `View.onHingeChange` (iOS 27.1+).
/// That API exposes status and angle only, with no hinge geometry, so the split layout
/// assumes the fold sits at the horizontal center of the inner display.
private struct HingeReader: ViewModifier {
    @Binding var state: HingeState?

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                state = context.hinge.map { $0.status == .closed ? .closed : .open }
            }
        } else {
            content
        }
    }
}

extension View {
    func readHinge(into state: Binding<HingeState?>) -> some View {
        modifier(HingeReader(state: state))
    }
}
