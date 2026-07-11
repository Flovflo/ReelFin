import Foundation
import Shared
import SwiftUI

enum NativePlayerTVChromeAction: CaseIterable, Equatable, Hashable {
    case subtitles
    case audio
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

    var controlShape: NativePlayerTVChromeControlShape { .circle }

    var accessibilityIdentifier: String {
        "native_player_\(accessibilityName)_button"
    }
}

enum NativePlayerTVChromeDestination: Equatable {
    case trackMenu(PlaybackTrackMenuKind)
    case videoPanel
    case playbackInfoPanel
    case itemInsightPanel
    case continueWatching
}

enum NativePlayerTVChromeControlShape: Equatable {
    case circle
    case capsule
}

enum NativePlayerTVChromeUtilityAction: CaseIterable, Equatable, Hashable {
    case info
    case insight
    case continueWatching

    var title: String {
        switch self {
        case .info: return "Info"
        case .insight: return "InSight"
        case .continueWatching: return "Continue Watching"
        }
    }

    var destination: NativePlayerTVChromeDestination {
        switch self {
        case .info: return .playbackInfoPanel
        case .insight: return .itemInsightPanel
        case .continueWatching: return .continueWatching
        }
    }

    var controlShape: NativePlayerTVChromeControlShape { .capsule }

    var accessibilityIdentifier: String {
        switch self {
        case .info: return "native_player_info_button"
        case .insight: return "native_player_insight_button"
        case .continueWatching: return "native_player_continue_watching_button"
        }
    }
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
    let referenceSize: CGSize
    let timelineY: CGFloat
    let utilityRowY: CGFloat
    let circleDiameter: CGFloat
    let circleSpacing: CGFloat
    let titleSize: CGFloat
    let eyebrowSize: CGFloat
    let iconSize: CGFloat
    let utilityHeight: CGFloat
    let utilitySpacing: CGFloat
    let titleMinimumScaleFactor: CGFloat
    let maximumTitleWidthRatio: CGFloat

    static let standard = NativePlayerTVChromeLayout(
        alignment: .bottom,
        gradientHeight: 360,
        horizontalPadding: 80,
        bottomPadding: 50,
        timelineHeight: 7,
        referenceSize: CGSize(width: 1_920, height: 1_080),
        timelineY: 900,
        utilityRowY: 985,
        circleDiameter: 70,
        circleSpacing: 24,
        titleSize: 54,
        eyebrowSize: 25,
        iconSize: 28,
        utilityHeight: 64,
        utilitySpacing: 24,
        titleMinimumScaleFactor: 0.58,
        maximumTitleWidthRatio: 0.68
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
    let onShowPlaybackInfo: () -> Void
    let onShowItemInsight: () -> Void
    let onContinueWatching: () -> Void
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

            VStack(alignment: .leading, spacing: 10) {
                headerRow(layout: layout)
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
                utilityBar(layout: layout)
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

    private func metadata(layout: NativePlayerTVChromeLayout) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let eyebrow = presentation.eyebrow {
                Text(eyebrow)
                    .font(.system(size: layout.eyebrowSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(presentation.title)
                    .font(.system(size: layout.titleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(layout.titleMinimumScaleFactor)

                if isBuffering {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.86))
                        .accessibilityLabel("Buffering")
                }
            }
        }
        .frame(maxWidth: layout.referenceSize.width * layout.maximumTitleWidthRatio, alignment: .leading)
        .shadow(color: .black.opacity(0.42), radius: 7, y: 2)
    }

#if os(tvOS)
    private func headerRow(layout: NativePlayerTVChromeLayout) -> some View {
        HStack {
            metadata(layout: layout)
            Spacer(minLength: 0)
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: layout.circleSpacing) {
                    ForEach(NativePlayerTVChromeAction.allCases, id: \.self) { action in
                        Button {
                            onInteraction()
                            if let trackMenuKind = action.trackMenuKind {
                                onShowTrackPicker(trackMenuKind)
                            } else {
                                onShowVideoPanel()
                            }
                        } label: {
                            Image(systemName: action.systemName)
                                .font(.system(size: layout.iconSize, weight: .semibold, design: .rounded))
                                .frame(width: layout.circleDiameter, height: layout.circleDiameter)
                                .glassEffect(.regular.interactive(), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .focusEffectDisabled(true)
                        .hoverEffectDisabled(true)
                        .focused($focusedControl, equals: .action(action))
                        .accessibilityLabel(action.title)
                        .accessibilityIdentifier(action.accessibilityIdentifier)
                    }
                }
            }
            .focusSection()
        }
        .frame(minHeight: 112, alignment: .bottom)
    }

    private func utilityBar(layout: NativePlayerTVChromeLayout) -> some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: layout.utilitySpacing) {
                ForEach(NativePlayerTVChromeUtilityAction.allCases, id: \.self) { action in
                    Button {
                        onInteraction()
                        perform(action)
                    } label: {
                        Text(action.title)
                            .font(.system(size: 23, weight: .semibold, design: .rounded))
                            .padding(.horizontal, action == .continueWatching ? 30 : 24)
                            .frame(height: layout.utilityHeight)
                            .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled(true)
                    .hoverEffectDisabled(true)
                    .focused($focusedControl, equals: .utility(action))
                    .accessibilityIdentifier(action.accessibilityIdentifier)
                }
            }
        }
        .focusSection()
    }

    private func perform(_ action: NativePlayerTVChromeUtilityAction) {
        switch action.destination {
        case .playbackInfoPanel: onShowPlaybackInfo()
        case .itemInsightPanel: onShowItemInsight()
        case .continueWatching: onContinueWatching()
        case .trackMenu, .videoPanel: break
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
