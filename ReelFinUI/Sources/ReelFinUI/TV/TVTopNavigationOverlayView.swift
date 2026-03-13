import SwiftUI

struct TVTopNavigationOverlayView: View {
    @Binding var selectedDestination: TVRootDestination
    let focusedDestination: FocusState<TVRootDestination?>.Binding
    let isVisible: Bool

    var body: some View {
        ZStack(alignment: .top) {
            if isVisible {
                TVTopBackdropOverlay()
                    .transition(.opacity)

                TVTopNavigationBar(
                    selectedDestination: $selectedDestination,
                    focusedDestination: focusedDestination
                )
                .padding(.top, 22)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isVisible)
    }
}
