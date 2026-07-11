import Foundation
import Shared
import SwiftUI

enum NativePlayerTVChromeAction: CaseIterable, Equatable, Hashable {
    case audio
    case subtitles
    case video

    var title: String {
        switch self {
        case .audio:
            return "Audio"
        case .subtitles:
            return "Sous-titres"
        case .video:
            return "Vidéo"
        }
    }

    var systemName: String {
        switch self {
        case .audio:
            return "waveform"
        case .subtitles:
            return "captions.bubble"
        case .video:
            return "display"
        }
    }

    var trackMenuKind: PlaybackTrackMenuKind? {
        switch self {
        case .audio:
            return .audio
        case .subtitles:
            return .subtitles
        case .video:
            return nil
        }
    }

    var destination: NativePlayerTVChromeDestination {
        trackMenuKind.map(NativePlayerTVChromeDestination.trackMenu) ?? .videoPanel
    }
}

enum NativePlayerTVChromeDestination: Equatable {
    case trackMenu(PlaybackTrackMenuKind)
    case videoPanel
}

struct NativePlayerTVChromeLayout: Equatable {
    enum Alignment: Equatable {
        case bottom
    }

    let alignment: Alignment
    let gradientHeight: CGFloat
    let horizontalPadding: CGFloat
    let bottomPadding: CGFloat
    let timelineHeight: CGFloat

    static let standard = NativePlayerTVChromeLayout(
        alignment: .bottom,
        gradientHeight: 500,
        horizontalPadding: 72,
        bottomPadding: 54,
        timelineHeight: 7
    )
}

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
    let onShowVideoPanel: () -> Void
    let onToggleChrome: () -> Void
    let onDismiss: () -> Void
    let isInteractionEnabled: Bool
    let preferredFocus: NativePlayerTVChromeFocus
    let onTVCommand: (NativePlayerTVTransportCommand) -> Void
#if os(tvOS)
    @Environment(\.resetFocus) private var resetFocus
    @Namespace private var chromeFocusNamespace
    @FocusState private var focusedControl: NativePlayerTVChromeFocus?
#endif

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
        let layout = NativePlayerTVChromeLayout.standard
        ZStack(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.10), location: 0.28),
                    .init(color: .black.opacity(0.72), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: layout.gradientHeight)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 16) {
                metadata
                NativePlayerTimelineView(
                    presentation: presentation,
                    playbackTime: playbackTime,
                    durationSeconds: durationSeconds,
                    onSeekRelative: onSeekRelative,
                    onSeekAbsolute: onSeekAbsolute,
                    onSelect: onToggleChrome,
                    focus: $focusedControl,
                    onCommand: onTVCommand
                )
                actionBar
            }
            .focusScope(chromeFocusNamespace)
            .defaultFocus($focusedControl, preferredFocus)
            .disabled(!isInteractionEnabled)
            .onChange(of: preferredFocus) { _, focus in
                guard isInteractionEnabled else { return }
                focusedControl = focus
                resetFocus(in: chromeFocusNamespace)
            }
            .onChange(of: isInteractionEnabled) { _, isEnabled in
                guard isEnabled else { return }
                focusedControl = preferredFocus
                resetFocus(in: chromeFocusNamespace)
            }
            .onAppear {
                guard isInteractionEnabled else { return }
                focusedControl = preferredFocus
                resetFocus(in: chromeFocusNamespace)
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(.bottom, layout.bottomPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
        .background(alignment: .topLeading) {
            PlayerAccessibilityMarkerView(identifier: "native_player_chrome")
                .frame(width: 1, height: 1)
        }
#endif
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let eyebrow = presentation.eyebrow {
                Text(eyebrow)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(presentation.title)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if isBuffering {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.86))
                        .accessibilityLabel("Buffering")
                }
            }
        }
        .shadow(color: .black.opacity(0.42), radius: 7, y: 2)
    }

#if os(tvOS)
    private var actionBar: some View {
        HStack {
            Spacer(minLength: 0)
            GlassEffectContainer(spacing: 18) {
                HStack(spacing: 18) {
                    ForEach(NativePlayerTVChromeAction.allCases, id: \.self) { action in
                        Button {
                            onInteraction()
                            if let trackMenuKind = action.trackMenuKind {
                                onShowTrackPicker(trackMenuKind)
                            } else {
                                onShowVideoPanel()
                            }
                        } label: {
                            Label(action.title, systemImage: action.systemName)
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 20)
                                .frame(height: 54)
                        }
                        .buttonStyle(.glass)
                        .focused($focusedControl, equals: .action(action))
                        .accessibilityIdentifier("native_player_\(action.accessibilityName)_button")
                    }
                }
            }
            .focusSection()
        }
    }
#endif

    private var presentation: NativePlayerChromePresentation {
        NativePlayerChromePresentation(
            item: item,
            playbackTime: playbackTime,
            durationSeconds: durationSeconds
        )
    }

}

private extension NativePlayerTVChromeAction {
    var accessibilityName: String {
        switch self {
        case .audio:
            return "audio"
        case .subtitles:
            return "subtitles"
        case .video:
            return "video"
        }
    }
}
