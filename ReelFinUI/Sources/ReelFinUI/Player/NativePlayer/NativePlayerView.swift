import Foundation
import NativeMediaCore
import PlaybackEngine
import Shared
import SwiftUI

struct NativePlayerView: View {
    let playbackURL: URL?
    let playbackHeaders: [String: String]
    let startTimeSeconds: Double?
    let item: MediaItem
    let diagnostics: [String]
    let errorMessage: String?
    let transportState: PlaybackTransportState
    let onSelectTrack: (PlaybackControlSelection) -> Void
    let onPlaybackTime: (Double) -> Void
    let onSkipSuggestion: (PlaybackSkipSuggestion) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var liveDiagnostics: [String] = []
    @State private var isPaused = false
    @State private var playbackTime: Double = 0
    @State private var localStartTimeSeconds: Double = 0
    @State private var seekGeneration = 0
    @State private var seekRequest: NativePlayerSeekRequest?
    @State private var pendingSeekTask: Task<Void, Never>?
    @State private var pendingSeekTarget: Double?
    @State private var pendingSeekDirection: NativePlayerSeekDirection = .forward
    @State private var committedSeekDirection: NativePlayerSeekDirection = .forward
    @State private var seekDisplayHoldUntil: Date?
    @State private var activeTrackMenu: PlaybackTrackMenuKind?
    @State private var subtitleSelectionMemory = NativePlayerSubtitleSelectionMemory()
    @State private var activeInformationPanel: NativePlayerInformationPanel?
    @State private var showsDiagnostics = false
    @State private var isChromeUserActive = true
#if os(tvOS)
    @State private var isChromeExplicitlyHidden = false
    @State private var isCircularScrubbing = false
    @State private var circularScrubCancelRequestToken: UInt = 0
#endif
    @State private var chromeAutoHideTask: Task<Void, Never>?
    @State private var isViewActive = false
    @State private var lastDeepEvidenceLogDate: Date?
    @State private var lastDeepEvidencePlaybackTime: Double?
    @State private var accessibilityEvidence = PlayerAccessibilityEvidenceState()
    @State private var accessibilityEvidenceExpiryTask: Task<Void, Never>?
#if os(tvOS)
    @State private var continueWatchingTransition = NativePlayerTVContinueWatchingTransition()
    @AppStorage(SubtitleBackgroundStyle.defaultsKey)
    private var subtitleBackgroundStyle: SubtitleBackgroundStyle = .transparent
    @FocusState private var remoteInputFocused: Bool
    @State private var preferredChromeFocus: NativePlayerTVChromeFocus = .timeline
    @State private var chromeFocusRequestToken: UInt = 0
    @FocusState private var isSkipActionFocused: Bool
#endif

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let playbackURL, routeViolation == nil {
                Group {
                    if isPacketDemuxedContainer {
                        NativeMatroskaSampleBufferPlayerView(
                            url: playbackURL,
                            headers: playbackHeaders,
                            container: containerFormat,
                            startTimeSeconds: resolvedStartTime,
                            seekRequest: seekRequest,
                            selectedAudioTrackID: transportState.selectedAudioTrackID,
                            selectedSubtitleTrackID: transportState.selectedSubtitleTrackID,
                            baseDiagnostics: diagnostics,
                            isPaused: $isPaused,
                            onDiagnostics: handleDiagnostics,
                            onPlaybackTime: handlePlaybackTime
                        )
                    } else {
                        NativeMP4SampleBufferPlayerView(
                            url: playbackURL,
                            headers: playbackHeaders,
                            startTimeSeconds: resolvedStartTime,
                            seekRequest: seekRequest,
                            baseDiagnostics: diagnostics,
                            isPaused: $isPaused,
                            onDiagnostics: handleDiagnostics,
                            onPlaybackTime: handlePlaybackTime
                        )
                    }
                }
                .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
#if os(tvOS)
            NativePlayerRemoteInputLayer(
                isEnabled: !shouldShowChrome,
                onCommand: tvCommandDispatcher.dispatch
            )
            .focused($remoteInputFocused)
            .onAppear(perform: updateRemoteInputFocus)
            .onChange(of: shouldShowChrome) { _, _ in updateRemoteInputFocus() }
            .ignoresSafeArea()
#endif
            if shouldShowDiagnosticsPanel || visibleErrorMessage != nil {
                NativePlayerDiagnosticsPanelView(
                    rows: shouldShowDiagnosticsPanel ? activeDiagnostics : [],
                    errorMessage: visibleErrorMessage
                )
            }
            if shouldShowChrome {
                NativePlayerTransportOverlayView(
                    item: item,
                    isPaused: $isPaused,
                    isCircularScrubbing: circularScrubActiveBinding,
                    showsDiagnostics: $showsDiagnostics,
                    circularScrubCancelRequestToken: playerCircularScrubCancelRequestToken,
                    playbackTime: displayPlaybackTime,
                    durationSeconds: durationSeconds,
                    isBuffering: isBuffering,
                    onSeekRelative: seekRelative,
                    onSeekAbsolute: seekAbsolute,
                    onInteraction: revealChrome,
                    onShowTrackPicker: showTrackPicker,
                    onShowVideoPanel: showVideoPanel,
                    onShowPlaybackInfo: showPlaybackInfo,
                    onShowItemInsight: showItemInsight,
                    onContinueWatching: continueWatching,
                    onToggleChrome: hideChrome,
                    onDismiss: { dismiss() },
                    isInteractionEnabled: activeTrackMenu == nil && activeInformationPanel == nil,
                    availableActions: NativePlayerTVChromeAvailability.actions(for: playbackControls),
                    preferredFocus: playerChromePreferredFocus,
                    focusRequestToken: playerChromeFocusRequestToken,
                    onTVCommand: dispatchTVCommand
                )
                .transition(.opacity)
            }
            if shouldShowChrome, let activeTrackMenu {
                Group {
#if os(tvOS)
                    NativePlayerAVKitMenuView(
                        mode: activeTrackMenu,
                        controls: playbackControls,
                        subtitleStyle: subtitleBackgroundStyle,
                        lastEnabledSubtitleID: subtitleSelectionMemory.lastEnabledID,
                        onSelect: handleAVKitMenuSelection,
                        onSelectStyle: { subtitleBackgroundStyle = $0 },
                        onDismiss: dismissActivePanel
                    )
#else
                    NativePlayerTrackSelectionMenuView(
                        mode: activeTrackMenu,
                        controls: playbackControls,
                        onSelect: handleTrackMenuSelection
                    )
                    .id(activeTrackMenu)
#endif
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(trackMenuPadding)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottomTrailing)))
            }
            if shouldShowChrome, let activeInformationPanel {
                Group {
                    switch activeInformationPanel {
                    case .video:
                        NativePlayerVideoInformationView(
                            qualityLabel: videoQualityLabel,
                            routeLabel: "Lecture directe originale"
                        )
                    case .playbackInfo:
                        NativePlayerVideoInformationView(
                            title: "Info",
                            accessibilityIdentifier: "native_player_info_panel",
                            qualityLabel: videoQualityLabel,
                            routeLabel: "Lecture directe originale"
                        )
                    case .insight:
                        NativePlayerItemInsightView(item: item, qualityLabel: videoQualityLabel)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(trackMenuPadding)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottomTrailing)))
            }
            if activeTrackMenu == nil,
               activeInformationPanel == nil,
               let skipSuggestion = transportState.activeSkipSuggestion {
                skipOverlay(suggestion: skipSuggestion)
            }
#if DEBUG && os(tvOS)
            if TVLiveUIAutomationPolicy.isEnabledForCurrentProcess {
                PlayerAccessibilityEvidenceView(
                    playbackTime: playbackTime,
                    transportState: accessibilityTransportState,
                    videoRenderingReady: accessibilityDiagnostics.videoRenderingReady,
                    audioRenderingReady: accessibilityDiagnostics.audioRenderingReady,
                    audioEvidenceRoute: "native_sample_buffer_audio_renderer_accepted",
                    isAdvancing: accessibilityEvidence.isAdvancing,
                    completedSeekTarget: accessibilityEvidence.completedSeekTarget,
                    didCompleteSeekToZero: accessibilityEvidence.didCompleteSeekToZero,
                    readerGeneration: accessibilityDiagnostics.readerGeneration,
                    errorMessage: visibleErrorMessage
                )
                .frame(width: 1, height: 1)
            }
#endif
        }
        .contentShape(Rectangle())
#if os(iOS)
        .onTapGesture {
            activeTrackMenu = nil
            activeInformationPanel = nil
            revealChrome()
        }
#endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native_engine_player_screen")
        .onAppear {
            isViewActive = true
            localStartTimeSeconds = startTimeSeconds ?? 0
            playbackTime = startTimeSeconds ?? 0
            lastDeepEvidenceLogDate = nil
            lastDeepEvidencePlaybackTime = nil
            accessibilityEvidence.reset()
            subtitleSelectionMemory.confirm(trackID: transportState.selectedSubtitleTrackID)
            revealChrome()
        }
        .onChange(of: transportState.selectedSubtitleTrackID) { _, trackID in
            subtitleSelectionMemory.confirm(trackID: trackID)
        }
        .task(id: transportState.activeSkipSuggestion) {
#if os(tvOS)
            guard transportState.activeSkipSuggestion != nil else {
                isSkipActionFocused = false
                updateRemoteInputFocus()
                return
            }
            // The transient Skip action replaces chrome focus while its marker is active. This
            // also handles the case where markers arrive before this view is mounted.
            chromeAutoHideTask?.cancel()
            chromeAutoHideTask = nil
            activeTrackMenu = nil
            activeInformationPanel = nil
            isChromeUserActive = false
            isChromeExplicitlyHidden = true
            remoteInputFocused = false
            await Task.yield()
            guard !Task.isCancelled,
                  transportState.activeSkipSuggestion != nil,
                  activeTrackMenu == nil,
                  activeInformationPanel == nil else { return }
            isSkipActionFocused = true
#endif
        }
        .onChange(of: playbackURL) { _, _ in
            localStartTimeSeconds = startTimeSeconds ?? 0
            playbackTime = startTimeSeconds ?? 0
            lastDeepEvidenceLogDate = nil
            lastDeepEvidencePlaybackTime = nil
            seekGeneration = 0
            seekRequest = nil
            pendingSeekTask?.cancel()
            pendingSeekTask = nil
            pendingSeekTarget = nil
            seekDisplayHoldUntil = nil
            liveDiagnostics = []
            accessibilityEvidence.reset()
            revealChrome()
        }
        .onChange(of: isPaused) { _, _ in
            accessibilityEvidence.setTransportState(accessibilityTransportState)
            if accessibilityTransportState != .playing {
                accessibilityEvidenceExpiryTask?.cancel()
                accessibilityEvidenceExpiryTask = nil
            }
#if os(tvOS)
            guard continueWatchingTransition.shouldRevealChromeAfterPauseChange() else { return }
#endif
            revealChrome()
        }
        .onChange(of: showsDiagnostics) { _, _ in
            revealChrome()
        }
        .onChange(of: isBuffering) { _, _ in
            revealChrome()
        }
        .onChange(of: visibleErrorMessage) { _, _ in
            revealChrome()
        }
        .onDisappear {
            isViewActive = false
            chromeAutoHideTask?.cancel()
            chromeAutoHideTask = nil
            pendingSeekTask?.cancel()
            accessibilityEvidenceExpiryTask?.cancel()
            pendingSeekTask = nil
            pendingSeekTarget = nil
            activeTrackMenu = nil
            activeInformationPanel = nil
            accessibilityEvidence.reset()
#if os(tvOS)
            remoteInputFocused = false
#endif
        }
        .animation(.easeInOut(duration: 0.22), value: shouldShowChrome)
        .onChange(of: shouldShowChrome) { _, isVisible in
#if os(tvOS)
            if isVisible {
                releaseRemoteInputFocus()
            } else {
                focusRemoteInputWhenChromeHidden()
            }
#endif
        }
#if os(tvOS)
        .onExitCommand {
            switch NativePlayerTVRemoteControlPolicy.menuAction(
                chromeVisible: shouldShowChrome,
                pickerVisible: activeTrackMenu != nil || activeInformationPanel != nil,
                isCircularScrubbing: isCircularScrubbing
            ) {
            case .dismissPicker:
                dismissActivePanel()
            case .cancelCircularScrub:
                circularScrubCancelRequestToken &+= 1
            case .hideChrome:
                hideChrome()
            case .exitPlayer:
                dismiss()
            }
        }
        .onPlayPauseCommand {
            if NativePlayerTVRemoteControlPolicy.playPauseAction(
                isCircularScrubbing: isCircularScrubbing
            ) == .dispatch {
                tvCommandDispatcher.dispatch(.playPause)
            }
        }
#endif
    }

    private var activeDiagnostics: [String] {
        liveDiagnostics.isEmpty ? diagnostics : liveDiagnostics
    }

    private var resolvedStartTime: Double {
        localStartTimeSeconds > 0 ? localStartTimeSeconds : (startTimeSeconds ?? 0)
    }

    private var durationSeconds: Double? {
        guard let ticks = item.runtimeTicks, ticks > 0 else { return nil }
        return Double(ticks) / 10_000_000
    }

    private var displayPlaybackTime: Double {
        pendingSeekTarget ?? playbackTime
    }

    private var isBuffering: Bool {
        activeDiagnostics.contains("state=buffering")
    }

    private var accessibilityDiagnostics: NativePlayerAccessibilityDiagnostics {
        NativePlayerAccessibilityDiagnostics(rows: activeDiagnostics)
    }

    private var accessibilityTransportState: PlayerAccessibilityTransportState {
        if visibleErrorMessage != nil { return .failed }
        if isPaused { return .paused }
        return accessibilityDiagnostics.transportState
    }

    private var shouldShowChrome: Bool {
#if os(tvOS)
        if isChromeExplicitlyHidden, activeTrackMenu == nil, activeInformationPanel == nil {
            return false
        }
#endif
        return activeTrackMenu != nil || activeInformationPanel != nil || NativePlayerChromeVisibilityPolicy.shouldShowChrome(
            isUserActive: isChromeUserActive,
            isPaused: isPaused,
            isBuffering: isBuffering,
            showsDiagnostics: shouldShowDiagnosticsPanel,
            hasError: visibleErrorMessage != nil,
            isPinnedForAutomation: keepsChromeVisibleForAutomation
        )
    }

    private var keepsChromeVisibleForAutomation: Bool {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let values = [
            environment["REELFIN_LIVE_UI_EXPECT_CUSTOM_CONTROLS"],
            environment["REELFIN_PLAYER_DEEP_EVIDENCE"]
        ].compactMap { $0?.lowercased() }
        return values.contains { ["1", "true", "yes", "on"].contains($0) }
#else
        return false
#endif
    }

    private var playbackControls: PlaybackControlsModel {
        PlaybackControlsModel.make(
            audioTracks: transportState.availableAudioTracks,
            subtitleTracks: transportState.availableSubtitleTracks,
            selectedAudioID: transportState.selectedAudioTrackID,
            selectedSubtitleID: transportState.selectedSubtitleTrackID,
            skipSuggestion: transportState.activeSkipSuggestion
        )
    }

    private var playerChromePreferredFocus: NativePlayerTVChromeFocus {
#if os(tvOS)
        preferredChromeFocus
#else
        .timeline
#endif
    }

    private var playerChromeFocusRequestToken: UInt {
#if os(tvOS)
        chromeFocusRequestToken
#else
        0
#endif
    }

    private var circularScrubActiveBinding: Binding<Bool> {
#if os(tvOS)
        $isCircularScrubbing
#else
        .constant(false)
#endif
    }

    private var playerCircularScrubCancelRequestToken: UInt {
#if os(tvOS)
        circularScrubCancelRequestToken
#else
        0
#endif
    }

    private func dispatchTVCommand(_ command: NativePlayerTVTransportCommand) {
#if os(tvOS)
        tvCommandDispatcher.dispatch(command)
#endif
    }

    private var trackMenuPadding: EdgeInsets {
#if os(tvOS)
        EdgeInsets(top: 0, leading: 0, bottom: 164, trailing: 86)
#else
        EdgeInsets(top: 0, leading: 20, bottom: 116, trailing: 20)
#endif
    }

    private var shouldShowDiagnosticsPanel: Bool {
#if os(iOS)
        false
#else
        showsDiagnostics
#endif
    }

    private var routeViolation: NativePlayerRouteViolation? {
        playbackURL.flatMap { NativePlayerRouteGuard.validateOriginalPlaybackURL($0).first }
    }

    private var visibleErrorMessage: String? {
        routeViolation?.localizedDescription ?? errorMessage
    }

    private var containerFormat: ContainerFormat {
        if diagnostics.contains(where: { $0 == "container=webm" }) { return .webm }
        if diagnostics.contains(where: { $0 == "container=mpegTS" }) { return .mpegTS }
        if diagnostics.contains(where: { $0 == "container=m2ts" }) { return .m2ts }
        return .matroska
    }

    private var isPacketDemuxedContainer: Bool {
        diagnostics.contains { line in
            line == "container=matroska" || line == "container=webm" || line == "container=mpegTS" || line == "container=m2ts"
        }
    }

    private func handleDiagnostics(_ rows: [String]) {
        DispatchQueue.main.async {
            guard isViewActive else { return }
            liveDiagnostics = rows
        }
    }

    private func handlePlaybackTime(_ seconds: Double) {
        guard seconds.isFinite else { return }
        DispatchQueue.main.async {
            guard isViewActive else { return }
            let nextPlaybackTime = max(0, seconds)
            let now = Date()
            clearExpiredSeekHold(now: now)
            if shouldHoldSeekDisplay(for: nextPlaybackTime, now: now) {
                return
            }
            playbackTime = nextPlaybackTime
            accessibilityEvidence.observe(
                playbackTime: nextPlaybackTime,
                generation: accessibilityDiagnostics.readerGeneration,
                transportState: accessibilityTransportState,
                observedAt: ProcessInfo.processInfo.systemUptime
            )
            scheduleAccessibilityEvidenceExpiryIfNeeded()
            clearSatisfiedSeekHold(for: nextPlaybackTime)
            onPlaybackTime(nextPlaybackTime)
            emitDeepSampleBufferEvidenceIfNeeded(
                seconds: nextPlaybackTime,
                rows: activeDiagnostics,
                now: now
            )
        }
    }

    private func seekRelative(_ delta: Double) {
        revealChrome()
        seekAbsolute((pendingSeekTarget ?? playbackTime) + delta)
    }

    private func seekAbsolute(_ seconds: Double) {
        revealChrome()
        let target = NativePlayerRemoteControlPolicy.clampedSeekTarget(
            from: seconds,
            delta: 0,
            durationSeconds: durationSeconds
        )
        accessibilityEvidence.beginSeek(target: target)
        pendingSeekDirection = NativePlayerRemoteControlPolicy.seekDirection(from: displayPlaybackTime, to: target)
        pendingSeekTarget = target
        playbackTime = target
        seekDisplayHoldUntil = Date().addingTimeInterval(3.0)
        scheduleSeekCommit(target)
    }

    @ViewBuilder
    private func skipOverlay(suggestion: PlaybackSkipSuggestion) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
#if os(iOS)
                PlaybackSkipButton(suggestion: suggestion) {
                    activateSkipSuggestion(suggestion)
                }
#else
                Button {
                    activateSkipSuggestion(suggestion)
                } label: {
                    Label(suggestion.title, systemImage: suggestion.systemImageName)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.glassProminent)
                .focused($isSkipActionFocused)
                .accessibilityIdentifier("native_player_skip_button")
#endif
            }
            .padding(.trailing, skipOverlayTrailingPadding)
            .padding(.bottom, skipOverlayBottomPadding)
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var skipOverlayTrailingPadding: CGFloat {
#if os(tvOS)
        80
#else
        28
#endif
    }

    private var skipOverlayBottomPadding: CGFloat {
#if os(tvOS)
        shouldShowChrome ? 350 : 76
#else
        96
#endif
    }

    private func activateSkipSuggestion(_ suggestion: PlaybackSkipSuggestion) {
        if let target = NativePlayerSampleBufferSkipPolicy.localSeekTarget(for: suggestion) {
            seekAbsolute(target)
        }
        onSkipSuggestion(suggestion)
    }

    private func scheduleSeekCommit(_ target: Double) {
        pendingSeekTask?.cancel()
        pendingSeekTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: NativePlayerRemoteControlPolicy.seekCommitDebounceNanoseconds)
            guard !Task.isCancelled, isViewActive else { return }
            commitSeek(target)
            pendingSeekTask = nil
        }
    }

    private func commitSeek(_ target: Double) {
        seekGeneration += 1
        seekRequest = NativePlayerSeekRequest(id: seekGeneration, targetSeconds: target)
        committedSeekDirection = pendingSeekDirection
        seekDisplayHoldUntil = Date().addingTimeInterval(4.0)
    }

    private func showTrackPicker(_ mode: PlaybackTrackMenuKind) {
        revealChrome()
        guard !playbackControls.options(for: mode).isEmpty else {
            activeTrackMenu = nil
            return
        }
#if os(tvOS)
        preferredChromeFocus = mode == .audio ? .audio : .subtitles
#endif
        activeInformationPanel = nil
        activeTrackMenu = mode
    }

    private func showVideoPanel() {
        revealChrome()
#if os(tvOS)
        preferredChromeFocus = .video
#endif
        activeTrackMenu = nil
        activeInformationPanel = .video
    }

    private func showPlaybackInfo() {
        revealChrome()
#if os(tvOS)
        preferredChromeFocus = .info
#endif
        activeTrackMenu = nil
        activeInformationPanel = .playbackInfo
    }

    private func showItemInsight() {
        revealChrome()
#if os(tvOS)
        preferredChromeFocus = .insight
#endif
        activeTrackMenu = nil
        activeInformationPanel = .insight
    }

    private func continueWatching() {
#if os(tvOS)
        preferredChromeFocus = .continueWatching
        continueWatchingTransition.beginContinueWatching(isPaused: isPaused)
#endif
        if NativePlayerTVContinueWatchingPolicy.shouldResume(isPaused: isPaused) {
            isPaused = false
        }
        hideChrome()
    }

    private func scheduleAccessibilityEvidenceExpiryIfNeeded() {
        accessibilityEvidenceExpiryTask?.cancel()
        guard accessibilityEvidence.isAdvancing else { return }
        accessibilityEvidenceExpiryTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64((PlayerAccessibilityEvidenceState.advancingFreshnessSeconds + 0.1) * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            accessibilityEvidence.expireAdvancing(observedAt: ProcessInfo.processInfo.systemUptime)
            accessibilityEvidenceExpiryTask = nil
        }
    }

    private func handleTrackMenuSelection(_ selection: PlaybackControlSelection) {
        activeTrackMenu = nil
#if os(tvOS)
        chromeFocusRequestToken = NativePlayerTVRemoteControlPolicy.nextFocusReturnToken(
            after: chromeFocusRequestToken
        )
#endif
        onSelectTrack(selection)
        revealChrome()
    }

#if os(tvOS)
    private func handleAVKitMenuSelection(_ selection: PlaybackControlSelection) {
        onSelectTrack(selection)
    }
#endif

    private func dismissActivePanel() {
        activeTrackMenu = nil
        activeInformationPanel = nil
#if os(tvOS)
        chromeFocusRequestToken = NativePlayerTVRemoteControlPolicy.nextFocusReturnToken(
            after: chromeFocusRequestToken
        )
#endif
        revealChrome()
    }

    private func hideChrome() {
        chromeAutoHideTask?.cancel()
        chromeAutoHideTask = nil
        activeTrackMenu = nil
        activeInformationPanel = nil
        isChromeUserActive = false
#if os(tvOS)
        isChromeExplicitlyHidden = true
        focusRemoteInputWhenChromeHidden()
#endif
    }

    private var videoQualityLabel: String {
        if let hdrLine = activeDiagnostics.first(where: { $0.hasPrefix("hdr=") }),
           !hdrLine.contains("hdr=sdr") {
            return hdrLine.replacingOccurrences(of: "hdr=", with: "").uppercased()
        }
        return "Originale"
    }

    private func shouldHoldSeekDisplay(for reportedSeconds: Double, now: Date) -> Bool {
        if let pendingSeekTarget, pendingSeekTask != nil {
            return !NativePlayerRemoteControlPolicy.hasReachedSeekTarget(
                reportedSeconds: reportedSeconds,
                targetSeconds: pendingSeekTarget,
                direction: pendingSeekDirection,
                tolerance: 0.75
            )
        }
        guard let seekRequest,
              let holdUntil = seekDisplayHoldUntil,
              now < holdUntil else {
            return false
        }
        return !NativePlayerRemoteControlPolicy.hasReachedSeekTarget(
            reportedSeconds: reportedSeconds,
            targetSeconds: seekRequest.targetSeconds,
            direction: committedSeekDirection,
            tolerance: 0.75
        )
    }

    private func clearSatisfiedSeekHold(for reportedSeconds: Double) {
        guard let seekRequest else { return }
        if NativePlayerRemoteControlPolicy.hasReachedSeekTarget(
            reportedSeconds: reportedSeconds,
            targetSeconds: seekRequest.targetSeconds,
            direction: committedSeekDirection,
            tolerance: 1.5
        ) {
            self.seekRequest = nil
            pendingSeekTarget = nil
            seekDisplayHoldUntil = nil
        }
    }

    private func clearExpiredSeekHold(now: Date) {
        guard let holdUntil = seekDisplayHoldUntil, now >= holdUntil else { return }
        seekRequest = nil
        pendingSeekTarget = nil
        seekDisplayHoldUntil = nil
    }

    private func emitDeepSampleBufferEvidenceIfNeeded(
        seconds: Double,
        rows: [String],
        now: Date
    ) {
        guard Self.isDeepPlaybackEvidenceEnabled, seconds.isFinite else { return }
        if let lastLogDate = lastDeepEvidenceLogDate,
           now.timeIntervalSince(lastLogDate) < Self.deepEvidenceIntervalSeconds {
            return
        }

        let delta = lastDeepEvidencePlaybackTime.map { seconds - $0 } ?? 0
        lastDeepEvidenceLogDate = now
        lastDeepEvidencePlaybackTime = seconds

        let packetLine = Self.firstLine(containing: "packets video=", in: rows)
        let audioLine = Self.firstLine(containing: "audioSamples rendered=", in: rows)
        let underrunLine = Self.firstLine(containing: "audioUnderruns=", in: rows)
        let driftLine = Self.firstLine(containing: "avDriftMs=", in: rows)
        let hdrLine = Self.firstLine(containing: "hdr=", in: rows)
        let videoPackets = Self.intValue(named: "video", in: packetLine) ?? 0
        let audioPackets = Self.intValue(named: "audio", in: packetLine) ?? 0
        let audioSamples = Self.intValue(named: "rendered", in: audioLine) ?? 0
        let audioRenderer = Self.value(named: "audioRendererBackend", in: rows) ?? "unknown"
        let droppedFrames = Self.intValue(named: "droppedFrames", in: rows) ?? 0
        let audioUnderruns = Self.intValue(named: "audioUnderruns", in: underrunLine) ?? 0
        let audioRebuffers = Self.intValue(named: "audioRebuffers", in: underrunLine) ?? 0
        let avDriftMs = Self.value(named: "avDriftMs", in: driftLine) ?? "unknown"
        let hdr = Self.value(named: "hdr", in: hdrLine) ?? "unknown"
        let dvProfile = Self.value(named: "dvProfile", in: hdrLine) ?? "none"
        PlayerDeepEvidenceSink.append(
            "nativeplayer.deep.tick — item=\(AppLogFormat.shortIdentifier(item.id)) current=\(String(format: "%.3f", seconds)) delta=\(String(format: "%.3f", delta)) state=\(Self.value(named: "state", in: rows) ?? "unknown") videoPackets=\(videoPackets) audioPackets=\(audioPackets) audioSamples=\(audioSamples) audioRenderer=\(audioRenderer) droppedFrames=\(droppedFrames) audioUnderruns=\(audioUnderruns) audioRebuffers=\(audioRebuffers) avDriftMs=\(avDriftMs) hdr=\(hdr) dvProfile=\(dvProfile)"
        )

        AppLog.playback.info(
            "nativeplayer.deep.tick — item=\(AppLogFormat.shortIdentifier(item.id), privacy: .public) current=\(seconds, format: .fixed(precision: 3)) delta=\(delta, format: .fixed(precision: 3)) state=\(Self.value(named: "state", in: rows) ?? "unknown", privacy: .public) videoPackets=\(Self.intValue(named: "video", in: packetLine) ?? 0, privacy: .public) audioPackets=\(Self.intValue(named: "audio", in: packetLine) ?? 0, privacy: .public) audioSamples=\(Self.intValue(named: "rendered", in: audioLine) ?? 0, privacy: .public) audioRenderer=\(Self.value(named: "audioRendererBackend", in: rows) ?? "unknown", privacy: .public) droppedFrames=\(Self.intValue(named: "droppedFrames", in: rows) ?? 0, privacy: .public) audioUnderruns=\(Self.intValue(named: "audioUnderruns", in: underrunLine) ?? 0, privacy: .public) audioRebuffers=\(Self.intValue(named: "audioRebuffers", in: underrunLine) ?? 0, privacy: .public) avDriftMs=\(Self.value(named: "avDriftMs", in: driftLine) ?? "unknown", privacy: .public) hdr=\(Self.value(named: "hdr", in: hdrLine) ?? "unknown", privacy: .public) dvProfile=\(Self.value(named: "dvProfile", in: hdrLine) ?? "none", privacy: .public)"
        )
    }

    private static var deepEvidenceIntervalSeconds: TimeInterval {
        5
    }

    private static var isDeepPlaybackEvidenceEnabled: Bool {
        let value = ProcessInfo.processInfo.environment["REELFIN_PLAYER_DEEP_EVIDENCE"] ?? ""
        return ["1", "true", "yes", "on"].contains(value.lowercased())
    }

    private static func firstLine(containing token: String, in rows: [String]) -> String? {
        rows.first { $0.contains(token) }
    }

    private static func value(named name: String, in rows: [String]) -> String? {
        rows.lazy.compactMap { value(named: name, in: $0) }.first
    }

    private static func intValue(named name: String, in rows: [String]) -> Int? {
        rows.lazy.compactMap { intValue(named: name, in: $0) }.first
    }

    private static func intValue(named name: String, in line: String?) -> Int? {
        guard let value = value(named: name, in: line) else { return nil }
        return Int(value)
    }

    private static func value(named name: String, in line: String?) -> String? {
        guard let line, let range = line.range(of: "\(name)=") else { return nil }
        let suffix = line[range.upperBound...]
        let end = suffix.firstIndex { $0 == " " || $0 == "\t" } ?? suffix.endIndex
        let value = String(suffix[..<end])
        return value.isEmpty ? nil : value
    }

    private func revealChrome() {
        isChromeUserActive = true
#if os(tvOS)
        isChromeExplicitlyHidden = false
        releaseRemoteInputFocus()
#endif
        scheduleChromeAutoHide()
    }

    private func togglePlayPause() {
        revealChrome()
        isPaused.toggle()
    }

    private func scheduleChromeAutoHide() {
        chromeAutoHideTask?.cancel()
        chromeAutoHideTask = nil
        guard NativePlayerChromeVisibilityPolicy.shouldAutoHide(
            isPaused: isPaused,
            isBuffering: isBuffering,
            showsDiagnostics: shouldShowDiagnosticsPanel,
            hasError: visibleErrorMessage != nil,
            isPinnedForAutomation: keepsChromeVisibleForAutomation
        ), activeTrackMenu == nil, activeInformationPanel == nil else {
            return
        }
        chromeAutoHideTask = Task { @MainActor in
            let delay = UInt64(NativePlayerChromeVisibilityPolicy.autoHideDelaySeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, activeTrackMenu == nil, activeInformationPanel == nil else { return }
            isChromeUserActive = false
#if os(tvOS)
            focusRemoteInputWhenChromeHidden()
#endif
        }
    }

#if os(tvOS)
    private var tvCommandDispatcher: NativePlayerTVCommandDispatcher {
        NativePlayerTVCommandDispatcher(
            onSelect: { shouldShowChrome ? hideChrome() : revealChrome() },
            onPlayPause: togglePlayPause,
            onMove: handleRemoteMove
        )
    }

    private func handleRemoteMove(_ direction: NativePlayerRemoteMoveDirection) {
        guard activeTrackMenu == nil, activeInformationPanel == nil else { return }
        guard let seekDelta = NativePlayerRemoteControlPolicy.relativeSeekSeconds(for: direction) else {
            revealChrome()
            return
        }
        seekRelative(seekDelta)
    }

    private func focusRemoteInputWhenChromeHidden() {
        updateRemoteInputFocus()
    }

    private func releaseRemoteInputFocus() {
        remoteInputFocused = false
    }

    private func updateRemoteInputFocus() {
        remoteInputFocused = isViewActive
            && !shouldShowChrome
            && transportState.activeSkipSuggestion == nil
    }
#endif
}

private enum NativePlayerInformationPanel: Equatable {
    case video
    case playbackInfo
    case insight
}
