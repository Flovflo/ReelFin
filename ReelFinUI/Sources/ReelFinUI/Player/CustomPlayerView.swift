import AVKit
import ImageCache
import PlaybackEngine
import Shared
import SwiftUI

enum CustomPlayerLaunchPresentationPolicy {
    static func showsInterruptionOverlay(
        phase: PlaybackBufferingState.Phase,
        reservoirSeconds: Double
    ) -> Bool {
        phase == .buffering && reservoirSeconds < 3
    }

    static func statusText(
        phase: PlaybackBufferingState.Phase,
        progress: Double
    ) -> String {
        switch phase {
        case .prebuffering:
            let percentage = Int((min(max(progress, 0), 1) * 100).rounded())
            return "Préparation de l’original · \(percentage) %"
        case .buffering:
            return "Reprise de la lecture"
        default:
            return "Ouverture de l’original"
        }
    }
}

enum CustomPlayerTVRemoteRouting {
    enum Input: Equatable {
        case menu
        case playPause
        case select
        case left
        case right
        case other
    }

    enum Action: Equatable {
        case handleMenu
        case togglePlayPause
        case toggleChrome
        case seekRelative(Double)
        case ignore
    }

    static let showsInlineAVKitControls = false

    static func action(for input: Input) -> Action {
        switch input {
        case .menu: return .handleMenu
        case .playPause: return .togglePlayPause
        case .select: return .toggleChrome
        case .left: return .seekRelative(NativePlayerRemoteControlPolicy.rewindSeconds)
        case .right: return .seekRelative(NativePlayerRemoteControlPolicy.fastForwardSeconds)
        case .other: return .ignore
        }
    }
}

enum CustomPlayerSkipFocusPolicy {
    static func shouldRequestFocus(hadSuggestion: Bool, hasSuggestion: Bool) -> Bool {
        !hadSuggestion && hasSuggestion
    }
}

/// Full-screen host for the NEW custom playback engine (flag-gated). Shows `engine.player` and an
/// original-first LOADING BAR overlay while the deep cache is being built (pre-buffer / mid-play
/// buffer) — instead of a silent freeze or a quality drop. The legacy player path is untouched.
struct CustomPlayerView: View {
    let engine: CustomPlaybackEngine
    var launchContext: LaunchContext?
    /// Host-provided dismissal. Required when the view is an INLINE overlay (tvOS) — there is no
    /// presentation for `@Environment(\.dismiss)` to pop there.
    var onRequestDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    /// Slow-launch escalation: past this delay with still no picture, the overlay stops pretending
    /// ("Lancement…") and says the server is slow, with Retry/Quit — never an endless bare spinner.
    @State private var launchIsSlow = false
    private let slowLaunchThresholdSeconds: UInt64 = 15
#if os(tvOS)
    @FocusState private var isSkipActionFocused: Bool
    @FocusState private var isRemoteInputFocused: Bool
    @Namespace private var playerFocusNamespace
    @State private var isChromeVisible = true
    @State private var isTransportPaused = false
    @State private var activeTVPanel: CustomPlayerTVPanel?
    @State private var pendingTVSeekTarget: Double?
    @State private var pendingTVSeekTask: Task<Void, Never>?
    @State private var chromeAutoHideTask: Task<Void, Never>?
    @State private var focusReturnToken: UInt = 0
#endif

    /// What the launch screen shows the instant Play is pressed — the immediate "your action is
    /// happening" feedback (a bare black screen on a TV reads as a crash).
    struct LaunchContext {
        let item: MediaItem
        let apiClient: JellyfinAPIClientProtocol
        let imagePipeline: ImagePipelineProtocol
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CustomPlayerSurface(
                player: engine.player,
                engine: engine
            )
                .ignoresSafeArea()
            launchOverlay
            if !isLaunching, engine.bufferingState.phase != .failed {
#if os(tvOS)
                tvRemoteInputLayer
                tvPlayerChrome
#else
                VStack {
                    HStack {
                        Spacer()
                        subtitlePicker
                    }
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.horizontal, 8)
#endif
            }
            subtitleCueOverlay
            skipOverlay
            overlay
        }
#if os(tvOS)
        .focusScope(playerFocusNamespace)
        .onPlayPauseCommand(perform: toggleTVPlayPause)
        .onExitCommand {
            handleTVMenu()
        }
        .onChange(of: engine.activeSkipSuggestion != nil) { hadSuggestion, hasSuggestion in
            guard CustomPlayerSkipFocusPolicy.shouldRequestFocus(
                hadSuggestion: hadSuggestion,
                hasSuggestion: hasSuggestion
            ) else {
                if !hasSuggestion { isSkipActionFocused = false }
                return
            }
            Task { @MainActor in
                await Task.yield()
                isSkipActionFocused = true
            }
        }
#endif
        .onAppear {
            // The one log line that separates "the player never presented" (screen stuck on the
            // detail while the engine plays unseen) from "the player is up but the picture froze".
            AppLog.ui.notice("customplayer.view.appeared")
#if os(tvOS)
            revealTVChrome()
#endif
#if os(iOS)
            OrientationManager.shared.lockLandscapeForPlayerPresentation()
#endif
        }
        .onDisappear {
            AppLog.ui.notice("customplayer.view.disappeared")
            // Picture in Picture outlives the view — only a real dismissal stops playback.
            if !engine.isPictureInPictureActive {
                engine.stop()
            }
#if os(tvOS)
            pendingTVSeekTask?.cancel()
            chromeAutoHideTask?.cancel()
            isRemoteInputFocused = false
#endif
#if os(iOS)
            // A compatible MKV replaces this view with `PlayerView` inside the SAME full-screen
            // cover. Restoring portrait here races after the native view's landscape request and
            // leaves the movie letterboxed in a portrait screen.
            if !engine.isHandingOffToNativePlayback {
                OrientationManager.shared.restorePortraitAfterPlayerDismissal()
            }
#endif
        }
    }

    @ViewBuilder
    private var overlay: some View {
        let state = engine.bufferingState
        if state.phase == .failed {
            // Honest, retryable error — the recovery ladder's last rung. Never a silent frozen frame.
            VStack(spacing: 14) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.9))
                Text(engine.errorMessage ?? "La lecture a échoué.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                Button {
                    engine.retry()
                } label: {
                    Label("Réessayer", systemImage: "arrow.clockwise")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.25))
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        } else if state.isLoadingBarVisible,
                  CustomPlayerLaunchPresentationPolicy.showsInterruptionOverlay(
                    phase: state.phase,
                    reservoirSeconds: state.reservoirSeconds
                  ) {
            bufferingGlassPanel(state: state)
        } else if let error = engine.errorMessage {
            Text(error)
                .font(.callout)
                .foregroundStyle(.white)
                .padding(16)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    /// True from the instant the player appears until the picture is PROVEN on screen. Keying the
    /// overlay off the phase alone dropped it at the startup-gate exit — leaving a bare black
    /// screen (reads as a crash on a TV) until the first frame actually rendered.
    private var isLaunching: Bool {
        let phase = engine.bufferingState.phase
        if phase == .failed || phase == .ended { return false }
        return phase == .idle || phase == .prebuffering || !engine.hasRenderedFirstFrame
    }

    /// Launch screen: from the instant the player appears until the FIRST RENDERED FRAME — the
    /// movie's backdrop + title + a big spinner (and the cushion progress once known). Instant,
    /// contextual feedback that the press registered; fades out into the video. Past
    /// `slowLaunchThresholdSeconds` it turns honest: the server is slow — Retry or Quit.
    @ViewBuilder
    private var launchOverlay: some View {
        let state = engine.bufferingState
        if isLaunching {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()
                    if let context = launchContext {
                        CachedRemoteImage(
                            itemID: context.item.id,
                            type: .backdrop,
                            width: 1280,
                            quality: 68,
                            contentMode: .fill,
                            apiClient: context.apiClient,
                            imagePipeline: context.imagePipeline
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .ignoresSafeArea()
                        .opacity(0.52)
                    }
                    LinearGradient(
                        colors: [
                            .black.opacity(0.10),
                            .black.opacity(0.28),
                            .black.opacity(0.88)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()

                    VStack {
                        Spacer()
                        HStack {
                            launchGlassPanel(state: state)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, launchHorizontalPadding)
                        .padding(.bottom, launchBottomPadding)
                    }
                }
            }
            .transition(.opacity)
            .animation(.easeOut(duration: 0.22), value: engine.hasRenderedFirstFrame)
            .task(id: engine.loadGeneration) {
                launchIsSlow = false
                try? await Task.sleep(nanoseconds: slowLaunchThresholdSeconds * 1_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    launchIsSlow = true
                }
            }
        }
    }

    @ViewBuilder
    private func launchGlassPanel(state: PlaybackBufferingState) -> some View {
        let panel = HStack(alignment: .center, spacing: 18) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    if let title = launchContext?.item.name, !title.isEmpty {
                        Text(title)
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                    }
                    if let badge = qualityBadge {
                        Text(badge.text)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(badge.tint.opacity(0.9), in: Capsule())
                            .foregroundStyle(.black)
                    }
                }

                Text(
                    CustomPlayerLaunchPresentationPolicy.statusText(
                        phase: state.phase,
                        progress: state.progress
                    )
                )
                .font(.callout)
                .foregroundStyle(.white.opacity(0.72))

                if state.phase == .prebuffering, state.targetSeconds > 0 {
                    ProgressView(value: state.progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 340)
                        .tint(.white)
                }

                if launchIsSlow {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Le serveur met plus de temps que prévu.")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.82))
                        slowLaunchActions
                    }
                    .padding(.top, 4)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: 420, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)

        if #available(iOS 26.0, tvOS 26.0, *) {
            GlassEffectContainer(spacing: 14) {
                panel
                    .glassEffect(
                        .regular.tint(.black.opacity(0.18)),
                        in: .rect(cornerRadius: 28)
                    )
            }
        } else {
            panel
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        }
    }

    @ViewBuilder
    private var slowLaunchActions: some View {
        HStack(spacing: 12) {
            Button {
                engine.retry()
            } label: {
                Label("Réessayer", systemImage: "arrow.clockwise")
            }
            Button(role: .cancel) {
                requestDismissal()
            } label: {
                Label("Quitter", systemImage: "xmark")
            }
        }
        .buttonStyle(.glass)
    }

    @ViewBuilder
    private func bufferingGlassPanel(state: PlaybackBufferingState) -> some View {
        let panel = HStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Text("Reprise de la lecture")
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)

        if #available(iOS 26.0, tvOS 26.0, *) {
            panel.glassEffect(
                .regular.tint(.black.opacity(0.22)),
                in: .rect(cornerRadius: 22)
            )
        } else {
            panel.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        }
    }

    private var launchHorizontalPadding: CGFloat {
#if os(tvOS)
        72
#else
        28
#endif
    }

    private var launchBottomPadding: CGFloat {
#if os(tvOS)
        64
#else
        32
#endif
    }

    /// External-subtitle cue rendered by the player itself (sidecar SRT/VTT — AVFoundation can't
    /// inject text tracks into a progressive asset). Bottom-centered, TV-readable.
    @ViewBuilder
    private var subtitleCueOverlay: some View {
        if let cue = engine.subtitles.currentCue, !cue.isEmpty {
            VStack {
                Spacer()
                Text(cue)
                    .font(.system(size: 34, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.9), radius: 3, x: 0, y: 1)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, 72)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// Skip intro/credits + next-episode suggestion (same resolver as the rest of the app).
    @ViewBuilder
    private var skipOverlay: some View {
        if let suggestion = engine.activeSkipSuggestion {
            VStack {
                Spacer()
                HStack {
                    Spacer()
#if os(iOS)
                    PlaybackSkipButton(suggestion: suggestion) {
                        engine.skipCurrentSegment()
                    }
#else
                    Button {
                        engine.skipCurrentSegment()
                    } label: {
                        Label(suggestion.title, systemImage: "forward.frame.fill")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 26)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.glassProminent)
                    .focused($isSkipActionFocused)
                    .accessibilityIdentifier("custom_player_skip_button")
#endif
                }
                .padding(.trailing, 48)
                .padding(.bottom, 96)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// External subtitle track picker — only shown when the source actually has sidecar tracks.
    @ViewBuilder
    private var subtitlePicker: some View {
        if !engine.subtitles.availableTracks.isEmpty {
            Menu {
                Button {
                    engine.subtitles.select(trackID: nil)
                } label: {
                    Label("Désactivés", systemImage: engine.subtitles.activeTrackID == nil ? "checkmark" : "captions.bubble")
                }
                ForEach(engine.subtitles.availableTracks) { track in
                    Button {
                        engine.subtitles.select(trackID: track.id)
                    } label: {
                        Label(track.label, systemImage: engine.subtitles.activeTrackID == track.id ? "checkmark" : "captions.bubble")
                    }
                }
            } label: {
                Image(systemName: engine.subtitles.activeTrackID == nil ? "captions.bubble" : "captions.bubble.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.45), in: Circle())
            }
        }
    }

    private var qualityBadge: (text: String, tint: Color)? {
        if engine.bufferingState.phase == .degradedSDR {
            return ("Qualité adaptée", .orange)
        }
        guard let label = engine.sourceQualityLabel else { return nil }
        return (label, .white)
    }

    private func requestDismissal() {
        AppLog.ui.notice("customplayer.remote.exit")
        if let onRequestDismiss {
            onRequestDismiss()
        } else {
            dismiss()
        }
    }

#if os(tvOS)
    @ViewBuilder
    private var tvPlayerChrome: some View {
        if isChromeVisible, let item = launchContext?.item ?? engine.currentMediaItem {
            NativePlayerTransportOverlayView(
                item: item,
                isPaused: $isTransportPaused,
                showsDiagnostics: .constant(false),
                playbackTime: pendingTVSeekTarget ?? engine.lastObservedSeconds,
                durationSeconds: customDurationSeconds,
                isBuffering: engine.bufferingState.phase == .buffering,
                onSeekRelative: seekTVRelative,
                onSeekAbsolute: seekTVAbsolute,
                onInteraction: revealTVChrome,
                onShowTrackPicker: showTVTrackPicker,
                onShowVideoPanel: showTVVideoPanel,
                onToggleChrome: hideTVChrome,
                onDismiss: requestDismissal
            )
            .id(focusReturnToken)
            .transition(.opacity)
        }

        if isChromeVisible, let activeTVPanel {
            Group {
                switch activeTVPanel {
                case let .tracks(mode):
                    NativePlayerTrackSelectionMenuView(
                        mode: mode,
                        controls: customPlaybackControls,
                        onSelect: handleTVTrackSelection
                    )
                case .video:
                    NativePlayerVideoInformationView(
                        qualityLabel: engine.sourceQualityLabel ?? "Originale",
                        routeLabel: engine.hasLocalCacheReservoir ? "Lecture directe optimisée" : "Lecture directe"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.init(top: 0, leading: 0, bottom: 164, trailing: 86))
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottomTrailing)))
        }
    }

    private var tvRemoteInputLayer: some View {
        NativePlayerRemoteInputLayer(
            isEnabled: !isChromeVisible,
            onSelect: revealTVChrome,
            onMove: handleTVRemoteMove
        )
        .focused($isRemoteInputFocused)
        .ignoresSafeArea()
    }

    private var customDurationSeconds: Double? {
        if let observed = engine.observedDurationSeconds { return observed }
        guard let ticks = (launchContext?.item ?? engine.currentMediaItem)?.runtimeTicks, ticks > 0 else { return nil }
        return Double(ticks) / 10_000_000
    }

    private var customPlaybackControls: PlaybackControlsModel {
        let subtitles = [
            PlaybackTrackOption(
                trackID: nil,
                title: "Désactivés",
                badge: nil,
                iconName: "captions.bubble",
                isSelected: engine.subtitles.activeTrackID == nil
            )
        ] + engine.subtitles.availableTracks.map { track in
            PlaybackTrackOption(
                trackID: track.id,
                title: track.label,
                badge: nil,
                iconName: "captions.bubble",
                isSelected: engine.subtitles.activeTrackID == track.id
            )
        }
        return PlaybackControlsModel(audioOptions: [], subtitleOptions: subtitles)
    }

    private func toggleTVPlayPause() {
        engine.togglePlayPause()
        isTransportPaused.toggle()
        revealTVChrome()
        AppLog.ui.notice("customplayer.remote.command — input=playPause")
    }

    private func handleTVRemoteMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .left:
            seekTVRelative(NativePlayerRemoteControlPolicy.rewindSeconds)
        case .right:
            seekTVRelative(NativePlayerRemoteControlPolicy.fastForwardSeconds)
        case .up, .down:
            revealTVChrome()
        @unknown default:
            break
        }
    }

    private func seekTVRelative(_ delta: Double) {
        seekTVAbsolute((pendingTVSeekTarget ?? engine.lastObservedSeconds) + delta)
    }

    private func seekTVAbsolute(_ seconds: Double) {
        let target = NativePlayerRemoteControlPolicy.clampedSeekTarget(
            from: seconds,
            delta: 0,
            durationSeconds: customDurationSeconds
        )
        pendingTVSeekTarget = target
        pendingTVSeekTask?.cancel()
        pendingTVSeekTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: NativePlayerRemoteControlPolicy.seekCommitDebounceNanoseconds)
            guard !Task.isCancelled, pendingTVSeekTarget == target else { return }
            engine.seek(toSeconds: target)
            pendingTVSeekTarget = nil
            pendingTVSeekTask = nil
            AppLog.ui.notice("customplayer.remote.command — input=seek target=\(target, privacy: .public)")
        }
        revealTVChrome()
    }

    private func showTVTrackPicker(_ mode: PlaybackTrackMenuKind) {
        activeTVPanel = .tracks(mode)
        revealTVChrome()
    }

    private func showTVVideoPanel() {
        activeTVPanel = .video
        revealTVChrome()
    }

    private func handleTVTrackSelection(_ selection: PlaybackControlSelection) {
        switch selection {
        case .audio:
            break
        case let .subtitle(trackID):
            engine.subtitles.select(trackID: trackID)
        }
        dismissTVPanel()
    }

    private func handleTVMenu() {
        switch NativePlayerTVRemoteControlPolicy.menuAction(
            chromeVisible: isChromeVisible,
            pickerVisible: activeTVPanel != nil
        ) {
        case .dismissPicker:
            dismissTVPanel()
        case .hideChrome:
            hideTVChrome()
        case .exitPlayer:
            requestDismissal()
        }
    }

    private func dismissTVPanel() {
        activeTVPanel = nil
        focusReturnToken = NativePlayerTVRemoteControlPolicy.nextFocusReturnToken(after: focusReturnToken)
        revealTVChrome()
    }

    private func revealTVChrome() {
        isChromeVisible = true
        isRemoteInputFocused = false
        scheduleTVChromeAutoHide()
    }

    private func hideTVChrome() {
        chromeAutoHideTask?.cancel()
        chromeAutoHideTask = nil
        activeTVPanel = nil
        isChromeVisible = false
        Task { @MainActor in
            await Task.yield()
            guard !isChromeVisible else { return }
            isRemoteInputFocused = true
        }
    }

    private func scheduleTVChromeAutoHide() {
        chromeAutoHideTask?.cancel()
        guard !isTransportPaused, activeTVPanel == nil else { return }
        chromeAutoHideTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64(NativePlayerChromeVisibilityPolicy.autoHideDelaySeconds * 1_000_000_000)
            )
            guard !Task.isCancelled, activeTVPanel == nil, !isTransportPaused else { return }
            hideTVChrome()
        }
    }
#endif
}

#if os(tvOS)
private enum CustomPlayerTVPanel: Equatable {
    case tracks(PlaybackTrackMenuKind)
    case video
}
#endif

/// AVKit host for the custom engine. The engine creates its `AVPlayerItem` asynchronously after
/// SwiftUI presents this controller. On iOS AVKit can leave its PlayerRemoteXPC video surface
/// detached in that sequence: audio advances, but the display stays black. Keep the presentation
/// lifecycle here, where AVKit exposes the only authoritative render signal.
private struct CustomPlayerSurface: UIViewControllerRepresentable {
    private static let playerScreenAccessibilityIdentifier = "native_player_screen"
    private static let renderReadyAccessibilityIdentifier = "custom_player_rendering_ready"
    private static let playerScreenMarkerTag = 0x5246_4350
    private static let renderReadyMarkerTag = 0x5246_4352

    let player: AVPlayer
    let engine: CustomPlaybackEngine

    func makeCoordinator() -> Coordinator { Coordinator(engine: engine) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        AppLog.playback.notice("customplayer.surface.make")
        installPlayerScreenAccessibilityMarker(in: controller)
        controller.player = player
        configureDisplayPolicy(on: controller)
#if os(tvOS)
        controller.showsPlaybackControls = CustomPlayerTVRemoteRouting.showsInlineAVKitControls
#else
        controller.showsPlaybackControls = true
#endif
        controller.allowsPictureInPicturePlayback = true
#if os(iOS)
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.canStartPictureInPictureAutomaticallyFromInline = false
#endif
        // ReelFin picks the media tracks itself. Letting AVKit select one while the custom engine
        // still prepares its item caused a second late reconfiguration of the render surface.
        controller.player?.appliesMediaSelectionCriteriaAutomatically = false
        controller.delegate = context.coordinator
        context.coordinator.startObserving(player: player, controller: controller)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        installPlayerScreenAccessibilityMarker(in: controller)
        if context.coordinator.shouldDeferPlayerAssignment(to: player, controller: controller) {
            return
        }
        if controller.player !== player {
            AppLog.playback.notice("customplayer.surface.player_reassigned")
            controller.player = player
            configureDisplayPolicy(on: controller)
            controller.player?.appliesMediaSelectionCriteriaAutomatically = false
            context.coordinator.startObserving(player: player, controller: controller)
        }
    }

    private func installPlayerScreenAccessibilityMarker(in controller: AVPlayerViewController) {
        controller.view.accessibilityIdentifier = Self.playerScreenAccessibilityIdentifier
        guard controller.view.viewWithTag(Self.playerScreenMarkerTag) == nil else { return }

        let marker = UIView()
        marker.tag = Self.playerScreenMarkerTag
        marker.isAccessibilityElement = true
        marker.accessibilityIdentifier = Self.playerScreenAccessibilityIdentifier
        marker.accessibilityLabel = "Player"
        marker.backgroundColor = .clear
        marker.isUserInteractionEnabled = false
        marker.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(marker)
        NSLayoutConstraint.activate([
            marker.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            marker.topAnchor.constraint(equalTo: controller.view.topAnchor),
            marker.widthAnchor.constraint(equalToConstant: 1),
            marker.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    private func configureDisplayPolicy(on controller: AVPlayerViewController) {
#if os(tvOS)
        if NativePlayerViewController.shouldApplyPreferredDisplayCriteriaAutomatically(
            isTVOS: true,
            isSimulator: NativePlayerViewController.isRunningInSimulator
        ) {
            controller.appliesPreferredDisplayCriteriaAutomatically = true
        }
#endif
    }

    @MainActor
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        private let engine: CustomPlaybackEngine
        private var itemObservation: NSKeyValueObservation?
        private var statusObservation: NSKeyValueObservation?
        private var readyForDisplayObservation: NSKeyValueObservation?
        private weak var controller: AVPlayerViewController?
        private weak var observedPlayer: AVPlayer?
#if os(iOS)
        private var didReattachForCurrentItem = false
        private var isTemporarilyDetachedForReattach = false
        private var observedItemIdentifier: ObjectIdentifier?
        private var reattachGeneration: UInt = 0
        private var reattachWorkItem: DispatchWorkItem?
#endif

        init(engine: CustomPlaybackEngine) { self.engine = engine }

        deinit {
#if os(iOS)
            reattachWorkItem?.cancel()
#endif
        }

        func startObserving(player: AVPlayer, controller: AVPlayerViewController) {
            self.controller = controller
            observedPlayer = player
            let currentItemState = player.currentItem == nil ? "none" : "present"
            AppLog.playback.notice(
                "customplayer.surface.observe_start — item=\(currentItemState, privacy: .public)"
            )
            observeReadyForDisplay(on: controller)
#if os(iOS)
            reattachWorkItem?.cancel()
            isTemporarilyDetachedForReattach = false
            didReattachForCurrentItem = false
            observedItemIdentifier = player.currentItem.map(ObjectIdentifier.init)
#endif
            statusObservation = nil
            itemObservation = player.observe(\.currentItem, options: [.new]) { [weak self] player, _ in
                Task { @MainActor in
                    guard let self else { return }
                    let currentItemState = player.currentItem == nil ? "none" : "present"
                    AppLog.playback.notice(
                        "customplayer.surface.item_changed — item=\(currentItemState, privacy: .public)"
                    )
#if os(iOS)
                    self.reattachWorkItem?.cancel()
                    self.isTemporarilyDetachedForReattach = false
                    self.didReattachForCurrentItem = false
                    self.observedItemIdentifier = player.currentItem.map(ObjectIdentifier.init)
#endif
                    self.removeRenderReadyMarker()
                    self.observeItemStatus(player: player)
                }
            }
            if player.currentItem != nil {
                observeItemStatus(player: player)
            }
        }

        func shouldDeferPlayerAssignment(to player: AVPlayer, controller: AVPlayerViewController) -> Bool {
#if os(iOS)
            return isTemporarilyDetachedForReattach
                && controller.player == nil
                && observedPlayer === player
#else
            return false
#endif
        }

        private func observeReadyForDisplay(on controller: AVPlayerViewController) {
            readyForDisplayObservation = nil
            notifyRenderReadyIfNeeded(on: controller)
            readyForDisplayObservation = controller.observe(\.isReadyForDisplay, options: [.new]) { [weak self] controller, _ in
                Task { @MainActor in
                    AppLog.playback.notice(
                        "customplayer.surface.ready_for_display — value=\(controller.isReadyForDisplay, privacy: .public)"
                    )
                    self?.notifyRenderReadyIfNeeded(on: controller)
                }
            }
        }

        private func notifyRenderReadyIfNeeded(on controller: AVPlayerViewController) {
            guard controller.isReadyForDisplay,
                  controller.player?.currentItem?.status == .readyToPlay
            else { return }
#if os(iOS)
            guard !isTemporarilyDetachedForReattach else { return }
#endif
            installRenderReadyMarker(in: controller)
            AppLog.playback.notice("customplayer.surface.render_ready")
            engine.reportRenderSurfaceReady()
        }

        private func installRenderReadyMarker(in controller: AVPlayerViewController) {
            guard controller.view.viewWithTag(CustomPlayerSurface.renderReadyMarkerTag) == nil else { return }

            let marker = UIView()
            marker.tag = CustomPlayerSurface.renderReadyMarkerTag
            marker.isAccessibilityElement = true
            marker.accessibilityIdentifier = CustomPlayerSurface.renderReadyAccessibilityIdentifier
            marker.accessibilityLabel = "Player rendering ready"
            marker.backgroundColor = .clear
            marker.isUserInteractionEnabled = false
            marker.translatesAutoresizingMaskIntoConstraints = false
            controller.view.addSubview(marker)
            NSLayoutConstraint.activate([
                marker.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
                marker.topAnchor.constraint(equalTo: controller.view.topAnchor),
                marker.widthAnchor.constraint(equalToConstant: 1),
                marker.heightAnchor.constraint(equalToConstant: 1)
            ])
        }

        private func removeRenderReadyMarker() {
            controller?.view.viewWithTag(CustomPlayerSurface.renderReadyMarkerTag)?.removeFromSuperview()
        }

        private func observeItemStatus(player: AVPlayer) {
            statusObservation = nil
            guard let item = player.currentItem else {
#if os(iOS)
                observedItemIdentifier = nil
#endif
                return
            }
#if os(iOS)
            observedItemIdentifier = ObjectIdentifier(item)
#endif
            AppLog.playback.notice(
                "customplayer.surface.item_status — status=\(item.status.rawValue, privacy: .public)"
            )
            if item.status == .readyToPlay {
                handleSurfaceItemReady(player: player, item: item)
                return
            }
            statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                AppLog.playback.notice(
                    "customplayer.surface.item_status_changed — status=\(item.status.rawValue, privacy: .public)"
                )
                guard item.status == .readyToPlay else { return }
                Task { @MainActor in
                    self?.handleSurfaceItemReady(player: player, item: item)
                }
            }
        }

        private func handleSurfaceItemReady(player: AVPlayer, item: AVPlayerItem) {
#if os(iOS)
            reattachIfNeeded(player: player, item: item)
#else
            guard player.currentItem === item, let controller else { return }
            notifyRenderReadyIfNeeded(on: controller)
#endif
        }

#if os(iOS)
        private func reattachIfNeeded(player: AVPlayer, item: AVPlayerItem) {
            guard !didReattachForCurrentItem,
                  observedItemIdentifier == ObjectIdentifier(item),
                  let controller
            else { return }

            didReattachForCurrentItem = true
            reattachWorkItem?.cancel()
            isTemporarilyDetachedForReattach = true
            reattachGeneration &+= 1
            let generation = reattachGeneration

            DispatchQueue.main.async { [weak self, weak controller, weak item] in
                guard let self, let controller, let item,
                      self.reattachGeneration == generation,
                      self.observedItemIdentifier == ObjectIdentifier(item),
                      player.currentItem === item
                else {
                    self?.isTemporarilyDetachedForReattach = false
                    return
                }

                let shouldResume = player.rate > 0 || player.timeControlStatus == .playing
                if shouldResume { player.pause() }
                self.removeRenderReadyMarker()
                AppLog.playback.notice("customplayer.avkit.render_surface.reattach — reason=item_ready_to_play")
                controller.player = nil

                let workItem = DispatchWorkItem { [weak self, weak controller, weak item] in
                    guard let self else { return }
                    defer {
                        self.isTemporarilyDetachedForReattach = false
                        self.reattachWorkItem = nil
                    }
                    guard let controller, let item,
                          self.reattachGeneration == generation,
                          self.observedItemIdentifier == ObjectIdentifier(item),
                          player.currentItem === item
                    else { return }
                    controller.player = player
                    controller.player?.appliesMediaSelectionCriteriaAutomatically = false
                    self.observeReadyForDisplay(on: controller)
                    if shouldResume { player.play() }
                }
                self.reattachWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
            }
        }
#endif

        nonisolated func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
            Task { @MainActor in self.engine.isPictureInPictureActive = true }
        }

        nonisolated func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            Task { @MainActor in
                self.engine.isPictureInPictureActive = false
                // The hosting view is long gone when PiP ends detached — stop cleanly then.
                if playerViewController.viewIfLoaded?.window == nil {
                    self.engine.stop()
                }
            }
        }

        nonisolated func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            completionHandler(true)
        }
    }
}
