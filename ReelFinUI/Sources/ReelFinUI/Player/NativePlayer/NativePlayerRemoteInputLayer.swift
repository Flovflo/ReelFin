import SwiftUI

#if os(tvOS)
struct NativePlayerRemoteInputLayer: View {
    let isEnabled: Bool
    let onSelect: () -> Void
    let onMove: (MoveCommandDirection) -> Void

    var body: some View {
        Button(action: onSelect) {
            Color.clear
                .contentShape(Rectangle())
        }
            .buttonStyle(.plain)
            .focusable(isEnabled)
            .focusEffectDisabled(true)
            .hoverEffectDisabled(true)
            .onMoveCommand(perform: onMove)
            .allowsHitTesting(isEnabled)
            .accessibilityHidden(true)
    }
}
#endif
