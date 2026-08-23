#if os(iOS)
import Shared
import SwiftUI

struct NativePlayerIOSChromeLayout: Equatable {
    let minimumHitTarget: CGFloat
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let transportSpacing: CGFloat
    let transportDiameter: CGFloat
    let primaryTransportDiameter: CGFloat
    let timelineHeight: CGFloat
    let volumeWidth: CGFloat
    let titleSize: CGFloat
    let isCompact: Bool

    static func metrics(width: CGFloat, height: CGFloat) -> Self {
        let compact = width < 760 || height < 400
        return Self(
            minimumHitTarget: 44,
            horizontalPadding: compact ? 18 : min(30, max(22, width * 0.035)),
            topPadding: compact ? 14 : 22,
            bottomPadding: compact ? 14 : 22,
            transportSpacing: compact ? 34 : min(58, max(42, width * 0.055)),
            transportDiameter: 62,
            primaryTransportDiameter: compact ? 78 : 86,
            timelineHeight: compact ? 44 : 48,
            volumeWidth: compact ? 132 : min(164, max(140, width * 0.18)),
            titleSize: compact ? 25 : 30,
            isCompact: compact
        )
    }
}

struct NativePlayerIOSTransportOverlayView: View {
    let item: MediaItem
    let capabilities: NativePlayerChromeCapabilities
    @Binding var isPaused: Bool
    let playbackTime: Double
    let durationSeconds: Double?
    let isBuffering: Bool
    let onSeekRelative: (Double) -> Void
    let onSeekAbsolute: (Double) -> Void
    let onInteraction: () -> Void
    let onShowTrackPicker: (PlaybackTrackMenuKind) -> Void
    let onShowVideoPanel: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = NativePlayerIOSChromeLayout.metrics(
                width: proxy.size.width,
                height: proxy.size.height
            )

            ZStack {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.16), location: 0.35),
                            .init(color: .black.opacity(0.64), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: max(170, min(280, proxy.size.height * 0.46)))
                }
                .allowsHitTesting(false)

                topControls(layout: layout)
                    .padding(.top, proxy.safeAreaInsets.top + layout.topPadding)
                    .padding(.horizontal, layout.horizontalPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                centerTransportControls(layout: layout)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                NativePlayerIOSBottomChrome(
                    presentation: presentation,
                    layout: layout,
                    actions: capabilities.iOSBottomActions,
                    isBuffering: isBuffering,
                    playbackTime: playbackTime,
                    durationSeconds: durationSeconds,
                    onSeekAbsolute: seekAbsolute,
                    onInteraction: onInteraction,
                    onShowTrackPicker: onShowTrackPicker,
                    onShowVideoPanel: onShowVideoPanel
                )
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.bottom, proxy.safeAreaInsets.bottom + layout.bottomPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }

    private func topControls(layout: NativePlayerIOSChromeLayout) -> some View {
        HStack(alignment: .top, spacing: 16) {
            NativePlayerIOSIconButton(
                systemName: "xmark",
                size: .large,
                accessibilityLabel: "Fermer le lecteur",
                accessibilityIdentifier: "native_player_close_button"
            ) {
                onInteraction()
                onDismiss()
            }

            if !capabilities.iOSTopActions.isEmpty {
                NativePlayerIOSGlassGroup(spacing: 14, height: 48, horizontalPadding: 15) {
                    ForEach(capabilities.iOSTopActions, id: \.self) { action in
                        if action == .airPlay {
                            NativePlayerRoutePickerButton()
                                .frame(
                                    width: layout.minimumHitTarget,
                                    height: layout.minimumHitTarget
                                )
                                .accessibilityLabel("AirPlay")
                                .accessibilityIdentifier("native_player_airplay_button")
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            if capabilities.supportsSystemVolume {
                NativePlayerVolumeControl()
                    .frame(width: layout.volumeWidth, height: 48)
            }
        }
    }

    private func centerTransportControls(layout: NativePlayerIOSChromeLayout) -> some View {
        GlassEffectContainer(spacing: layout.transportSpacing) {
            HStack(spacing: layout.transportSpacing) {
                NativePlayerIOSIconButton(
                    systemName: "gobackward.10",
                    size: .transport,
                    diameter: layout.transportDiameter,
                    accessibilityLabel: "Reculer de 10 secondes",
                    accessibilityIdentifier: "native_player_seek_backward_10"
                ) {
                    onInteraction()
                    onSeekRelative(-10)
                }

                NativePlayerIOSIconButton(
                    systemName: isPaused ? "play.fill" : "pause.fill",
                    size: .primaryTransport,
                    diameter: layout.primaryTransportDiameter,
                    accessibilityLabel: isPaused ? "Lire" : "Pause",
                    accessibilityIdentifier: "native_player_play_pause_button"
                ) {
                    onInteraction()
                    isPaused.toggle()
                }

                NativePlayerIOSIconButton(
                    systemName: "goforward.10",
                    size: .transport,
                    diameter: layout.transportDiameter,
                    accessibilityLabel: "Avancer de 10 secondes",
                    accessibilityIdentifier: "native_player_seek_forward_10"
                ) {
                    onInteraction()
                    onSeekRelative(10)
                }
            }
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
    let layout: NativePlayerIOSChromeLayout
    let actions: [NativePlayerIOSBottomAction]
    let isBuffering: Bool
    let playbackTime: Double
    let durationSeconds: Double?
    let onSeekAbsolute: (Double) -> Void
    let onInteraction: () -> Void
    let onShowTrackPicker: (PlaybackTrackMenuKind) -> Void
    let onShowVideoPanel: () -> Void

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
                height: layout.timelineHeight,
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
                    .font(.system(size: layout.titleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Image(systemName: "chevron.right")
                    .font(.system(size: max(16, layout.titleSize * 0.58), weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))

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
        NativePlayerIOSGlassGroup(spacing: 12, height: 48, horizontalPadding: 10) {
            ForEach(actions, id: \.self) { action in
                NativePlayerIOSIconButton(
                    systemName: systemName(for: action),
                    size: .compact,
                    accessibilityLabel: accessibilityLabel(for: action),
                    accessibilityIdentifier: accessibilityIdentifier(for: action)
                ) {
                    onInteraction()
                    perform(action)
                }
            }
        }
    }

    private func perform(_ action: NativePlayerIOSBottomAction) {
        switch action {
        case .videoInformation:
            onShowVideoPanel()
        case .audio:
            onShowTrackPicker(.audio)
        case .subtitles:
            onShowTrackPicker(.subtitles)
        }
    }

    private func systemName(for action: NativePlayerIOSBottomAction) -> String {
        switch action {
        case .videoInformation: "gauge.with.dots.needle.50percent"
        case .audio: "waveform"
        case .subtitles: "captions.bubble"
        }
    }

    private func accessibilityLabel(for action: NativePlayerIOSBottomAction) -> String {
        switch action {
        case .videoInformation: "Informations vidéo"
        case .audio: "Audio"
        case .subtitles: "Sous-titres"
        }
    }

    private func accessibilityIdentifier(for action: NativePlayerIOSBottomAction) -> String {
        switch action {
        case .videoInformation: "native_player_video_button"
        case .audio: "native_player_audio_button"
        case .subtitles: "native_player_subtitles_button"
        }
    }
}
#endif
