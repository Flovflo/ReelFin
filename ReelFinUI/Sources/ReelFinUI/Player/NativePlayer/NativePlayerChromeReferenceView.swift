#if DEBUG && os(iOS)
import Shared
import SwiftUI

/// Deterministic UI-test surface rendered by the same controls as real playback. It deliberately
/// owns no media engine so screenshot validation never depends on a server or decoder warm-up.
public struct ReelFinPlayerChromeReferenceView: View {
    @State private var isPaused = true
    @State private var playbackTime: Double = 445
    @State private var activePanel: ReferencePanel?
    @State private var audioID = "audio-fr"
    @State private var subtitleID: String? = "subtitle-fr"
    @State private var transitionState = NativePlayerTrackTransitionState(
        confirmedAudioID: "audio-fr",
        confirmedSubtitleID: "subtitle-fr"
    )
    @State private var isDismissed = false
    @State private var isChromeVisible = true

    public init() {}

    public var body: some View {
        ZStack {
            Color.black
                .contentShape(Rectangle())
                .onTapGesture {
                    if activePanel != nil {
                        activePanel = nil
                    } else if !isDismissed {
                        isChromeVisible.toggle()
                    }
                }
                .ignoresSafeArea()

            if isDismissed {
                Button("Rouvrir le lecteur") {
                    isDismissed = false
                    isChromeVisible = true
                }
                .buttonStyle(.glassProminent)
            } else if isChromeVisible {
                NativePlayerTransportOverlayView(
                    item: item,
                    capabilities: .customAVPlayer(controls: controls),
                    isPaused: $isPaused,
                    isCircularScrubbing: .constant(false),
                    showsDiagnostics: .constant(false),
                    circularScrubCancelRequestToken: 0,
                    playbackTime: playbackTime,
                    durationSeconds: 2_643,
                    isBuffering: false,
                    onSeekRelative: { playbackTime = clamped(playbackTime + $0) },
                    onSeekAbsolute: { playbackTime = clamped($0) },
                    onInteraction: {},
                    onShowTrackPicker: { activePanel = .tracks($0) },
                    onShowVideoPanel: { activePanel = .video },
                    onShowSettingsPanel: {},
                    onToggleChrome: {},
                    onDismiss: { isDismissed = true },
                    isInteractionEnabled: activePanel == nil,
                    availableActions: [],
                    preferredFocus: .timeline,
                    focusRequestToken: 0,
                    onTVCommand: { _ in }
                )

                if let activePanel {
                    panel(activePanel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.init(top: 0, leading: 20, bottom: 112, trailing: 20))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native_player_chrome_reference")
        .background(alignment: .topLeading) {
            ZStack {
                PlayerAccessibilityMarkerView(
                    identifier: "native_player_chrome_reference_state",
                    value: referenceState
                )
                if activePanel == .video {
                    PlayerAccessibilityMarkerView(identifier: "native_player_video_panel")
                }
            }
            .frame(width: 1, height: 1)
        }
        .onAppear {
            OrientationManager.shared.lockLandscapeForPlayerPresentation()
        }
        .onDisappear {
            OrientationManager.shared.restorePortraitAfterPlayerDismissal()
        }
    }

    @ViewBuilder
    private func panel(_ panel: ReferencePanel) -> some View {
        switch panel {
        case let .tracks(mode):
            NativePlayerTrackSelectionMenuView(
                mode: mode,
                controls: controls,
                transitionState: transitionState,
                onSelect: select
            )
        case .video:
            NativePlayerVideoInformationView(
                qualityLabel: "4K · HEVC",
                routeLabel: "Lecture directe originale"
            )
        }
    }

    private func select(_ selection: PlaybackControlSelection) {
        transitionState.request(selection)
        switch selection {
        case let .audio(trackID):
            audioID = trackID
        case let .subtitle(trackID):
            subtitleID = trackID
        }
        transitionState.confirm(audioID: audioID, subtitleID: subtitleID)
        activePanel = nil
    }

    private func clamped(_ seconds: Double) -> Double {
        min(max(0, seconds), 2_643)
    }

    private var controls: PlaybackControlsModel {
        PlaybackControlsModel(
            audioOptions: [
                track("audio-fr", "Français", badge: "E-AC3 5.1", selected: audioID == "audio-fr"),
                track("audio-en", "Anglais", badge: "VO · E-AC3 5.1", selected: audioID == "audio-en")
            ],
            subtitleOptions: [
                track(nil, "Désactivés", selected: subtitleID == nil),
                track("subtitle-fr", "Français", badge: "Complet", selected: subtitleID == "subtitle-fr"),
                track("subtitle-en", "Anglais", badge: "SDH", selected: subtitleID == "subtitle-en")
            ]
        )
    }

    private var referenceState: String {
        "chrome=\(isChromeVisible ? "visible" : "hidden");paused=\(isPaused);time=\(Int(playbackTime));audio=\(audioID);subtitle=\(subtitleID ?? "off");panel=\(activePanel?.value ?? "none")"
    }

    private func track(
        _ id: String?,
        _ title: String,
        badge: String? = nil,
        selected: Bool
    ) -> PlaybackTrackOption {
        PlaybackTrackOption(
            trackID: id,
            title: title,
            badge: badge,
            iconName: nil,
            isSelected: selected
        )
    }

    private var item: MediaItem {
        MediaItem(
            id: "player-reference",
            name: "Sterling Point",
            mediaType: .episode,
            year: 2026,
            runtimeTicks: 26_430_000_000,
            seriesName: "Sterling Point",
            indexNumber: 2,
            parentIndexNumber: 1
        )
    }
}

private enum ReferencePanel: Equatable {
    case tracks(PlaybackTrackMenuKind)
    case video

    var value: String {
        switch self {
        case let .tracks(kind): "tracks-\(kind)"
        case .video: "video"
        }
    }
}
#endif

#if DEBUG && os(tvOS)
import Shared
import SwiftUI

/// Hermetic tvOS route for exercising the real production focus graph without a Jellyfin server.
/// It starts with chrome hidden so the first Down press validates the exact Siri Remote path that
/// previously required an extra reveal gesture.
public struct ReelFinTVPlayerChromeReferenceView: View {
    @Environment(\.resetFocus) private var resetFocus
    @State private var isPaused = false
    @State private var isChromeVisible = false
    @State private var activePanel: TVReferencePanel?
    @State private var focusRequestToken: UInt = 0
    @FocusState private var isHiddenInputFocused: Bool
    @Namespace private var hiddenInputFocusScope

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isChromeVisible {
                NativePlayerTransportOverlayView(
                    item: item,
                    capabilities: .customAVPlayer(controls: controls),
                    isPaused: $isPaused,
                    isCircularScrubbing: .constant(false),
                    showsDiagnostics: .constant(false),
                    circularScrubCancelRequestToken: 0,
                    playbackTime: 445,
                    durationSeconds: 2_643,
                    isBuffering: false,
                    onSeekRelative: { _ in },
                    onSeekAbsolute: { _ in },
                    onInteraction: {},
                    onShowTrackPicker: { _ in },
                    onShowVideoPanel: {},
                    onShowSettingsPanel: showSettings,
                    onToggleChrome: hideChrome,
                    onDismiss: {},
                    isInteractionEnabled: activePanel == nil,
                    availableActions: NativePlayerTVChromeAvailability.actions(for: controls),
                    preferredFocus: .settings,
                    focusRequestToken: focusRequestToken,
                    onTVCommand: dispatcher.dispatch
                )
                .transition(.opacity)
            }

            if isChromeVisible, let activePanel {
                Group {
                    switch activePanel {
                    case .settings:
                        NativePlayerTVSettingsView(
                            onShowPlaybackInfo: { self.activePanel = .playbackInfo },
                            onShowItemInsight: {},
                            onContinueWatching: hideChrome
                        )
                    case .playbackInfo:
                        NativePlayerVideoInformationView(
                            title: "Info",
                            accessibilityIdentifier: "native_player_info_panel",
                            qualityLabel: "4K · HEVC",
                            routeLabel: "Lecture directe originale"
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.init(top: 0, leading: 0, bottom: 164, trailing: 86))
            }

            NativePlayerRemoteInputLayer(
                isEnabled: !isChromeVisible,
                focus: $isHiddenInputFocused,
                onCommand: dispatcher.dispatch
            )
            .prefersDefaultFocus(!isChromeVisible, in: hiddenInputFocusScope)
            .focusScope(hiddenInputFocusScope)
            .defaultFocus($isHiddenInputFocused, true, priority: .userInitiated)
            .ignoresSafeArea()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native_player_tv_chrome_reference")
        .background(alignment: .topLeading) {
            ZStack {
                PlayerAccessibilityMarkerView(
                    identifier: "native_player_tv_chrome_reference_state",
                    value: referenceState
                )
                if activePanel == .playbackInfo {
                    PlayerAccessibilityMarkerView(identifier: "native_player_info_panel")
                }
            }
            .frame(width: 1, height: 1)
        }
        .task {
            await Task.yield()
            restoreHiddenInputFocus()
        }
        .onChange(of: isChromeVisible) { _, visible in
            if visible {
                isHiddenInputFocused = false
            } else {
                Task { @MainActor in
                    await Task.yield()
                    restoreHiddenInputFocus()
                }
            }
        }
    }

    private var dispatcher: NativePlayerTVCommandDispatcher {
        NativePlayerTVCommandDispatcher(
            onSelect: { isChromeVisible ? hideChrome() : revealChrome() },
            onPlayPause: {
                isPaused.toggle()
                revealChrome()
            },
            onMove: { _ in revealChrome() },
            onOpenSettings: showSettings
        )
    }

    private func revealChrome() {
        activePanel = nil
        isChromeVisible = true
        focusRequestToken &+= 1
    }

    private func hideChrome() {
        activePanel = nil
        isChromeVisible = false
    }

    private func showSettings() {
        isChromeVisible = true
        activePanel = .settings
        focusRequestToken &+= 1
    }

    private func restoreHiddenInputFocus() {
        guard !isChromeVisible else { return }
        resetFocus(in: hiddenInputFocusScope)
        isHiddenInputFocused = true
    }

    private var referenceState: String {
        "chrome=\(isChromeVisible ? "visible" : "hidden");panel=\(activePanel?.value ?? "none");inputFocused=\(isHiddenInputFocused)"
    }

    private var controls: PlaybackControlsModel {
        PlaybackControlsModel(
            audioOptions: [
                PlaybackTrackOption(
                    trackID: "audio-fr",
                    title: "Français",
                    badge: "E-AC3 5.1",
                    iconName: nil,
                    isSelected: true
                ),
                PlaybackTrackOption(
                    trackID: "audio-en",
                    title: "Anglais",
                    badge: "VO · E-AC3 5.1",
                    iconName: nil,
                    isSelected: false
                )
            ],
            subtitleOptions: [
                PlaybackTrackOption(
                    trackID: nil,
                    title: "Désactivés",
                    badge: nil,
                    iconName: nil,
                    isSelected: true
                ),
                PlaybackTrackOption(
                    trackID: "subtitle-fr",
                    title: "Français",
                    badge: "Complet",
                    iconName: nil,
                    isSelected: false
                )
            ]
        )
    }

    private var item: MediaItem {
        MediaItem(
            id: "tv-player-reference",
            name: "Sterling Point",
            mediaType: .episode,
            year: 2026,
            runtimeTicks: 26_430_000_000,
            seriesName: "Sterling Point",
            indexNumber: 2,
            parentIndexNumber: 1
        )
    }
}

private enum TVReferencePanel: Equatable {
    case settings
    case playbackInfo

    var value: String {
        switch self {
        case .settings: "settings"
        case .playbackInfo: "info"
        }
    }
}
#endif
