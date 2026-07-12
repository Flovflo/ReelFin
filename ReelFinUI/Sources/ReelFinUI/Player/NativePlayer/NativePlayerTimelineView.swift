import SwiftUI

struct NativePlayerTimelineView: View {
    let presentation: NativePlayerChromePresentation
    let playbackTime: Double
    let durationSeconds: Double?
    let onSeekRelative: (Double) -> Void
    let onSeekAbsolute: (Double) -> Void
    let onSelect: () -> Void
#if os(tvOS)
    @Binding var isPaused: Bool
    @Binding var isCircularScrubbing: Bool
    let circularScrubCancelRequestToken: UInt
    let focus: FocusState<NativePlayerTVChromeFocus?>.Binding
    let availableActions: [NativePlayerTVChromeAction]
    let onCommand: (NativePlayerTVTransportCommand) -> Void
#endif
    @State private var scrubValue: Double?
#if os(tvOS)
    @State private var circularScrubCoordinator = TVRemoteCircularScrubCoordinator()
    @State private var isCircularScrubGestureAvailable = false
#endif

    var body: some View {
        VStack(spacing: 5) {
            scrubberControl
            timeLabels
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native_player_timeline")
#if os(tvOS)
        .onChange(of: focus.wrappedValue) { _, nextFocus in
            if nextFocus != .timeline {
                apply(circularScrubCoordinator.focusChanged(isTimelineFocused: false))
                isCircularScrubGestureAvailable = false
            }
        }
        .onChange(of: circularScrubCancelRequestToken) { _, _ in
            apply(circularScrubCoordinator.back())
        }
        .onDisappear {
            _ = circularScrubCoordinator.abandon()
            scrubValue = nil
            isCircularScrubbing = false
            isCircularScrubGestureAvailable = false
        }
        .background(alignment: .topLeading) {
#if DEBUG
            if TVLiveUIAutomationPolicy.isEnabledForCurrentProcess {
                ZStack {
                    PlayerAccessibilityMarkerView(
                        identifier: "native_player_circular_scrub_available",
                        value: isCircularScrubGestureAvailable ? "true" : "false"
                    )
                    PlayerAccessibilityMarkerView(
                        identifier: "native_player_circular_scrub_state",
                        value: circularScrubCoordinator.evidenceState.rawValue
                    )
                    PlayerAccessibilityMarkerView(
                        identifier: "native_player_circular_scrub_preview_bucket",
                        value: TVRemoteCircularScrubCoordinator.previewBucket(seconds: scrubValue) ?? "none"
                    )
                }
                .frame(width: 1, height: 1)
            }
#endif
        }
#endif
    }

    @ViewBuilder
    private var scrubberControl: some View {
#if os(tvOS)
        NativePlayerTVProgressScrubberView(
            playbackTime: scrubValue ?? playbackTime,
            durationSeconds: durationSeconds,
            focus: focus,
            isScrubbing: circularScrubCoordinator.isActive,
            onSelect: handleTVSelect,
            onMove: handleTVMove,
            onScrubBegin: handleCircularScrubBegin,
            onScrubUpdate: handleCircularScrubUpdate,
            onScrubCancel: handleCircularScrubCancel,
            onGestureAvailabilityChanged: { isCircularScrubGestureAvailable = $0 }
        )
#else
        Slider(
            value: scrubBinding,
            in: 0...max(durationSeconds ?? max(playbackTime, 1), 1),
            onEditingChanged: handleScrubEditing
        )
#endif
    }

    private var timeLabels: some View {
#if os(tvOS)
        GeometryReader { proxy in
            ZStack {
                Text(tvCurrentTimeText)
                    .position(
                        x: NativePlayerTVTimelineLabelLayout.currentCenterX(
                            progress: tvProgress,
                            width: proxy.size.width
                        ),
                        y: 13
                    )
                Text(tvRemainingTimeText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
        }
        .frame(height: 26)
        .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundStyle(.white.opacity(0.82))
        .shadow(color: .black.opacity(0.32), radius: 4, y: 1)
#else
        HStack(spacing: 20) {
            Text(presentation.currentTimeText)
            Spacer(minLength: 0)
            Text(presentation.remainingTimeText)
        }
        .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
        .foregroundStyle(.white.opacity(0.82))
        .shadow(color: .black.opacity(0.32), radius: 4, y: 1)
        .frame(height: 26)
#endif
    }

    private var scrubBinding: Binding<Double> {
        Binding(
            get: { scrubValue ?? playbackTime },
            set: { scrubValue = $0 }
        )
    }

    private func handleScrubEditing(_ isEditing: Bool) {
        guard !isEditing, let scrubValue else { return }
        onSeekAbsolute(scrubValue)
        self.scrubValue = nil
    }

#if os(tvOS)
    private func handleCircularScrubBegin(_ sample: TVRemoteScrubSample) {
        guard let durationSeconds else { return }
        apply(circularScrubCoordinator.begin(
            sample: sample,
            originalTime: playbackTime,
            duration: durationSeconds,
            wasPlaying: !isPaused,
            isTimelineFocused: focus.wrappedValue == .timeline
        ))
    }

    private func handleCircularScrubUpdate(_ sample: TVRemoteScrubSample) {
        apply(circularScrubCoordinator.update(sample))
    }

    private func handleCircularScrubCancel() {
        apply(circularScrubCoordinator.cancelGesture())
    }

    private func handleTVSelect() {
        let transition = circularScrubCoordinator.select()
        if transition.consumesInput {
            apply(transition)
        } else {
            onSelect()
        }
    }

    private func handleTVMove(_ direction: NativePlayerRemoteMoveDirection) {
        apply(circularScrubCoordinator.move(direction))
    }

    private func apply(_ transition: TVRemoteCircularScrubTransition) {
        for effect in transition.effects {
            switch effect {
            case let .setPaused(value):
                isPaused = value
            case let .setPreview(value):
                scrubValue = value
            case let .seekAbsolute(seconds):
                onSeekAbsolute(seconds)
            case let .seekRelative(seconds):
                onSeekRelative(seconds)
            case let .moveFocus(direction):
                onCommand(.move(direction))
                focus.wrappedValue = NativePlayerTVChromeFocusGraph.destination(
                    from: .timeline,
                    direction: direction,
                    availableActions: availableActions
                )
            }
        }
        isCircularScrubbing = circularScrubCoordinator.isActive
    }

    private var tvCurrentTimeText: String {
        guard let scrubValue else { return presentation.currentTimeText }
        return tvTimeText(scrubValue)
    }

    private var tvRemainingTimeText: String {
        guard let scrubValue else { return presentation.remainingTimeText }
        guard let durationSeconds, durationSeconds.isFinite, durationSeconds > 0 else { return "--:--" }
        return "-\(tvTimeText(max(0, durationSeconds - scrubValue)))"
    }

    private var tvProgress: Double {
        guard let scrubValue else { return presentation.progress }
        guard let durationSeconds, durationSeconds > 0, scrubValue.isFinite else { return 0 }
        return min(max(scrubValue / durationSeconds, 0), 1)
    }

    private func tvTimeText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainingSeconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
#endif
}
