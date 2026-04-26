#if os(iOS)
import Shared
import SwiftUI

struct NativePlayerIOSTransportOverlayView: View {
    let item: MediaItem
    @Binding var isPaused: Bool
    let playbackTime: Double
    let durationSeconds: Double?
    let isBuffering: Bool
    let onSeekRelative: (Double) -> Void
    let onSeekAbsolute: (Double) -> Void
    let onInteraction: () -> Void
    let onShowTrackPicker: (PlaybackTrackMenuKind) -> Void
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let horizontalPadding = max(20, min(30, proxy.size.width * 0.045))
            let volumeWidth = min(164, max(128, proxy.size.width * 0.32))
            let transportSpacing = max(34, min(58, proxy.size.width * 0.10))

            ZStack {
                topControls(volumeWidth: volumeWidth)
                    .padding(.top, proxy.safeAreaInsets.top + 26)
                    .padding(.horizontal, horizontalPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                centerTransportControls(spacing: transportSpacing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                NativePlayerIOSBottomChrome(
                    presentation: presentation,
                    isBuffering: isBuffering,
                    playbackTime: playbackTime,
                    durationSeconds: durationSeconds,
                    onSeekAbsolute: seekAbsolute,
                    onInteraction: onInteraction,
                    onShowTrackPicker: onShowTrackPicker
                )
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, proxy.safeAreaInsets.bottom + 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }

    private func topControls(volumeWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 16) {
            NativePlayerIOSIconButton(systemName: "xmark", size: .large) {
                onInteraction()
                onDismiss()
            }
            .accessibilityLabel("Fermer le lecteur")

            NativePlayerIOSGlassGroup(spacing: 14, height: 44) {
                NativePlayerIOSIconButton(systemName: "rectangle.on.rectangle", size: .compact) {
                    onInteraction()
                }
                .accessibilityLabel("Picture in Picture")

                NativePlayerRoutePickerButton()
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("AirPlay")
            }

            Spacer(minLength: 8)

            NativePlayerVolumeControl()
                .frame(width: volumeWidth, height: 44)
        }
    }

    private func centerTransportControls(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            NativePlayerIOSIconButton(systemName: "gobackward.10", size: .transport) {
                onInteraction()
                onSeekRelative(-10)
            }
            .accessibilityLabel("Reculer de 10 secondes")

            NativePlayerIOSIconButton(systemName: isPaused ? "play.fill" : "pause.fill", size: .primaryTransport) {
                onInteraction()
                isPaused.toggle()
            }
            .accessibilityLabel(isPaused ? "Lire" : "Pause")

            NativePlayerIOSIconButton(systemName: "goforward.10", size: .transport) {
                onInteraction()
                onSeekRelative(10)
            }
            .accessibilityLabel("Avancer de 10 secondes")
        }
    }

    private func seekAbsolute(_ seconds: Double) {
        onInteraction()
        onSeekAbsolute(seconds)
    }

    private var presentation: NativePlayerChromePresentation {
        NativePlayerChromePresentation(
            item: item,
            playbackTime: playbackTime,
            durationSeconds: durationSeconds
        )
    }
}

private struct NativePlayerIOSBottomChrome: View {
    let presentation: NativePlayerChromePresentation
    let isBuffering: Bool
    let playbackTime: Double
    let durationSeconds: Double?
    let onSeekAbsolute: (Double) -> Void
    let onInteraction: () -> Void
    let onShowTrackPicker: (PlaybackTrackMenuKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 28) {
                titleBlock
                Spacer(minLength: 24)
                bottomTrackControls
            }

            NativePlayerIOSTimelineView(
                presentation: presentation,
                playbackTime: playbackTime,
                durationSeconds: durationSeconds,
                onSeekAbsolute: onSeekAbsolute
            )
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow = presentation.eyebrow {
                Text(eyebrow)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(presentation.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if isBuffering {
                    Text("Buffering")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.86))
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .nativePlayerIOSGlassCapsule()
                }
            }
        }
        .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
    }

    private var bottomTrackControls: some View {
        NativePlayerIOSGlassGroup(spacing: 18, height: 44) {
            NativePlayerIOSIconButton(systemName: "text.bubble", size: .compact) {
                onInteraction()
                onShowTrackPicker(.subtitles)
            }
            .accessibilityLabel("Sous-titres")

            NativePlayerIOSIconButton(systemName: "waveform", size: .compact) {
                onInteraction()
                onShowTrackPicker(.audio)
            }
            .accessibilityLabel("Audio")
        }
    }
}
#endif
