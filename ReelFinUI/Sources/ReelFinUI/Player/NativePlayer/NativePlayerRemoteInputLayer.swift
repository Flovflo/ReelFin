import SwiftUI

#if os(tvOS)
struct NativePlayerRemoteInputLayer: View {
    let isEnabled: Bool
    let onCommand: (NativePlayerTVTransportCommand) -> Void

    var body: some View {
        Button {
            onCommand(.select)
        } label: {
            Color.clear
                .contentShape(Rectangle())
        }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .focusEffectDisabled(true)
            .hoverEffectDisabled(true)
            .onMoveCommand { direction in
                guard let direction = remoteDirection(from: direction) else { return }
                onCommand(.move(direction))
            }
            .allowsHitTesting(isEnabled)
            .accessibilityHidden(true)
    }

    private func remoteDirection(from direction: MoveCommandDirection) -> NativePlayerRemoteMoveDirection? {
        switch direction {
        case .left: return .left
        case .right: return .right
        case .up: return .up
        case .down: return .down
        @unknown default: return nil
        }
    }
}
#endif
