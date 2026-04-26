import Foundation
import Shared
import SwiftUI

struct NativePlayerTransportOverlayView: View {
    let item: MediaItem
    @Binding var isPaused: Bool
    @Binding var showsDiagnostics: Bool
    let playbackTime: Double
    let durationSeconds: Double?
    let isBuffering: Bool
    let onSeekRelative: (Double) -> Void
    let onSeekAbsolute: (Double) -> Void
    let onInteraction: () -> Void
    let onShowTrackPicker: (PlaybackTrackMenuKind) -> Void
    let onDismiss: () -> Void

    @ViewBuilder
    var body: some View {
#if os(iOS)
        NativePlayerIOSTransportOverlayView(
            item: item,
            isPaused: $isPaused,
            playbackTime: playbackTime,
            durationSeconds: durationSeconds,
            isBuffering: isBuffering,
            onSeekRelative: onSeekRelative,
            onSeekAbsolute: onSeekAbsolute,
            onInteraction: onInteraction,
            onShowTrackPicker: onShowTrackPicker,
            onDismiss: onDismiss
        )
#else
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                metadataAndRoundControls
                NativePlayerTimelineView(
                    presentation: presentation,
                    playbackTime: playbackTime,
                    durationSeconds: durationSeconds,
                    onSeekAbsolute: onSeekAbsolute
                )
                bottomActions
            }
            .padding(.horizontal, 38)
            .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
#endif
    }

    private var metadataAndRoundControls: some View {
        HStack(alignment: .bottom, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                if let eyebrow = presentation.eyebrow {
                    Text(eyebrow)
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.35), radius: 5, y: 1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(presentation.title)
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .shadow(color: .black.opacity(0.38), radius: 7, y: 2)
                    if isBuffering {
                        bufferingBadge
                    }
                }
            }
            Spacer(minLength: 32)
            rightRoundControls
        }
    }

    @ViewBuilder
    private var rightRoundControls: some View {
        rightRoundControlsContent
    }

    private var rightRoundControlsContent: some View {
        HStack(spacing: 22) {
            NativePlayerGlassCircleButton(systemName: "text.bubble", accessibilityLabel: "Subtitles", action: {
                onShowTrackPicker(.subtitles)
            })
            NativePlayerGlassCircleButton(systemName: "waveform", accessibilityLabel: "Audio", action: {
                onShowTrackPicker(.audio)
            }, isProminent: true)
            NativePlayerGlassCircleButton(systemName: "rectangle.on.rectangle", accessibilityLabel: "Picture in Picture") { onInteraction() }
        }
    }

    @ViewBuilder
    private var bottomActions: some View {
        bottomActionsContent
    }

    private var bottomActionsContent: some View {
        HStack(spacing: 24) {
            NativePlayerGlassPillButton(title: "Info") {
                onInteraction()
                showsDiagnostics.toggle()
            }
            NativePlayerGlassPillButton(title: "InSight") {
                onInteraction()
                showsDiagnostics.toggle()
            }
            NativePlayerGlassPillButton(title: "Continue Watching", action: {
                onInteraction()
                isPaused = false
            }, isProminent: true)
        }
    }

    private var bufferingBadge: some View {
        Text("Buffering")
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .reelFinGlassCapsule(tint: Color.white.opacity(0.10), stroke: Color.white.opacity(0.14), shadowOpacity: 0.12, shadowRadius: 10, shadowYOffset: 5)
    }

    private var presentation: NativePlayerChromePresentation {
        NativePlayerChromePresentation(
            item: item,
            playbackTime: playbackTime,
            durationSeconds: durationSeconds
        )
    }

}
