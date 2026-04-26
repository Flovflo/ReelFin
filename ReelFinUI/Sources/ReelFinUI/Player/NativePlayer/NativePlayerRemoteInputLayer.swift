import SwiftUI

#if os(tvOS)
struct NativePlayerRemoteInputLayer: View {
    let isEnabled: Bool
    let onReveal: () -> Void
    let onPlayPause: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .focusable(isEnabled)
            .onTapGesture(perform: onReveal)
            .onPlayPauseCommand(perform: onPlayPause)
            .allowsHitTesting(isEnabled)
            .accessibilityHidden(true)
    }
}
#endif
