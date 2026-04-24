#if os(tvOS)
import SwiftUI

struct TVTopNavigationOverlayView: View {
    @Binding var selectedDestination: TVRootDestination
    let focusedDestination: FocusState<TVRootDestination?>.Binding
    let isVisible: Bool
    let appearance: TVTopNavigationAppearance
    let onMoveCommand: (TVRootDestination, MoveCommandDirection) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            if isVisible {
                TVTopBackdropOverlay(appearance: appearance)
                    .transition(.opacity)

                TVTopNavigationBar(
                    selectedDestination: $selectedDestination,
                    focusedDestination: focusedDestination,
                    appearance: appearance,
                    onMoveCommand: onMoveCommand
                )
                .padding(.top, 22)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}
#endif
