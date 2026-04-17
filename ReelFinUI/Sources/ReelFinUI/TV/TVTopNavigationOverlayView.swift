#if os(tvOS)
import SwiftUI

struct TVTopNavigationOverlayView: View {
    @Binding var selectedDestination: TVRootDestination
    let focusedDestination: FocusState<TVRootDestination?>.Binding
    let isVisible: Bool
    let appearance: TVTopNavigationAppearance
    let isFocusable: Bool
    let onMoveDownFromNavigation: (TVRootDestination) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            if isVisible {
                TVTopBackdropOverlay(appearance: appearance)
                    .transition(.opacity)

                TVTopNavigationBar(
                    selectedDestination: $selectedDestination,
                    focusedDestination: focusedDestination,
                    appearance: appearance,
                    isFocusable: isFocusable,
                    onMoveDownFromNavigation: onMoveDownFromNavigation
                )
                .padding(.top, 22)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}
#endif
