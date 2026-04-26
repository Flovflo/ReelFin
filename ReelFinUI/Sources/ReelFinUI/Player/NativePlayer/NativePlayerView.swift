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
    @State private var showsDiagnostics = false
    @State private var isChromeUserActive = true
    @State private var chromeAutoHideTask: Task<Void, Never>?
    @State private var isViewActive = false
#if os(tvOS)
    @FocusState private var remoteInputFocused: Bool
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
                onReveal: revealChrome,
                onPlayPause: togglePlayPause
            )
            .focused($remoteInputFocused)
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
                    showsDiagnostics: $showsDiagnostics,
                    playbackTime: displayPlaybackTime,
                    durationSeconds: durationSeconds,
                    isBuffering: isBuffering,
                    onSeekRelative: seekRelative,
                    onSeekAbsolute: seekAbsolute,
                    onInteraction: revealChrome,
                    onShowTrackPicker: showTrackPicker,
                    onDismiss: { dismiss() }
                )
                .transition(.opacity)
            }
            if shouldShowChrome, let activeTrackMenu {
                NativePlayerTrackSelectionMenuView(
                    mode: activeTrackMenu,
                    controls: playbackControls,
                    onSelect: handleTrackMenuSelection
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(trackMenuPadding)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottomTrailing)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            activeTrackMenu = nil
            revealChrome()
        }
        .accessibilityIdentifier("native_engine_player_screen")
        .onAppear {
            isViewActive = true
            localStartTimeSeconds = startTimeSeconds ?? 0
            playbackTime = startTimeSeconds ?? 0
            revealChrome()
        }
        .onChange(of: playbackURL) { _, _ in
            localStartTimeSeconds = startTimeSeconds ?? 0
            playbackTime = startTimeSeconds ?? 0
            seekGeneration = 0
            seekRequest = nil
            pendingSeekTask?.cancel()
            pendingSeekTask = nil
            pendingSeekTarget = nil
            seekDisplayHoldUntil = nil
            revealChrome()
        }
        .onChange(of: isPaused) { _, _ in
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
            pendingSeekTask = nil
            pendingSeekTarget = nil
            activeTrackMenu = nil
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
            if activeTrackMenu != nil {
                dismissTrackMenu()
            } else {
                dismiss()
            }
        }
        .onPlayPauseCommand {
            togglePlayPause()
        }
        .onMoveCommand(perform: handleRemoteMove)
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

    private var shouldShowChrome: Bool {
        activeTrackMenu != nil || NativePlayerChromeVisibilityPolicy.shouldShowChrome(
            isUserActive: isChromeUserActive,
            isPaused: isPaused,
            isBuffering: isBuffering,
            showsDiagnostics: shouldShowDiagnosticsPanel,
            hasError: visibleErrorMessage != nil
        )
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
            clearSatisfiedSeekHold(for: nextPlaybackTime)
            onPlaybackTime(nextPlaybackTime)
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
        pendingSeekDirection = NativePlayerRemoteControlPolicy.seekDirection(from: displayPlaybackTime, to: target)
        pendingSeekTarget = target
        playbackTime = target
        seekDisplayHoldUntil = Date().addingTimeInterval(3.0)
        scheduleSeekCommit(target)
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
        activeTrackMenu = mode
    }

    private func handleTrackMenuSelection(_ selection: PlaybackControlSelection) {
        activeTrackMenu = nil
        onSelectTrack(selection)
        revealChrome()
    }

    private func dismissTrackMenu() {
        activeTrackMenu = nil
        revealChrome()
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

    private func revealChrome() {
        isChromeUserActive = true
#if os(tvOS)
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
            hasError: visibleErrorMessage != nil
        ), activeTrackMenu == nil else {
            return
        }
        chromeAutoHideTask = Task { @MainActor in
            let delay = UInt64(NativePlayerChromeVisibilityPolicy.autoHideDelaySeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, activeTrackMenu == nil else { return }
            isChromeUserActive = false
#if os(tvOS)
            focusRemoteInputWhenChromeHidden()
#endif
        }
    }

#if os(tvOS)
    private func handleRemoteMove(_ direction: MoveCommandDirection) {
        guard activeTrackMenu == nil else { return }
        guard let remoteDirection = nativeRemoteDirection(from: direction),
              let seekDelta = NativePlayerRemoteControlPolicy.relativeSeekSeconds(for: remoteDirection) else {
            revealChrome()
            return
        }
        seekRelative(seekDelta)
    }

    private func nativeRemoteDirection(from direction: MoveCommandDirection) -> NativePlayerRemoteMoveDirection? {
        switch direction {
        case .left:
            return .left
        case .right:
            return .right
        case .up:
            return .up
        case .down:
            return .down
        @unknown default:
            return nil
        }
    }

    private func focusRemoteInputWhenChromeHidden() {
        DispatchQueue.main.async {
            guard isViewActive, !shouldShowChrome else { return }
            remoteInputFocused = true
        }
    }

    private func releaseRemoteInputFocus() {
        DispatchQueue.main.async {
            guard isViewActive else { return }
            remoteInputFocused = false
        }
    }
#endif
}
