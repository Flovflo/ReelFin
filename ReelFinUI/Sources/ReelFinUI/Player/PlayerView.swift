import PlaybackEngine
import Shared
import SwiftUI

struct PlayerView: View {
    @ObservedObject var session: PlaybackSessionController
    let item: MediaItem
    let onDismiss: () -> Void

    @State private var spinnerRotation: Double = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            // Native iOS/tvOS player controls (scrubber, audio/subtitle menu, PiP, AirPlay).
            NativePlayerViewController(player: session.player)
                .ignoresSafeArea()
        }
        .safeAreaInset(edge: .top) {
            topBarControls
                .padding(.horizontal, 12)
                .padding(.top, 6)
        }
        .onDisappear {
            session.pause()
            OrientationManager.shared.lock = .portrait
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        }
        .onAppear {
            OrientationManager.shared.lock = .allButUpsideDown
            spinnerRotation = 0
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                spinnerRotation = 360
            }
        }
    }

    private var topBarControls: some View {
        HStack(spacing: 10) {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Circle())
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
