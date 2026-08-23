import Foundation
import PlaybackEngine
import Shared
import SwiftUI

struct NativePlayerSeekRequest: Equatable {
    let id: Int
    let targetSeconds: Double
}

struct NativePlayerChromePresentation: Equatable {
    let eyebrow: String?
    let title: String
    let currentTimeText: String
    let remainingTimeText: String
    let progress: Double

    init(item: MediaItem, playbackTime: Double, durationSeconds: Double?) {
        self.eyebrow = Self.eyebrow(for: item)
        self.title = Self.title(for: item)
        self.currentTimeText = Self.formatElapsed(playbackTime)
        self.remainingTimeText = Self.formatRemaining(playbackTime: playbackTime, durationSeconds: durationSeconds)
        self.progress = Self.progress(playbackTime: playbackTime, durationSeconds: durationSeconds)
    }

    private static func title(for item: MediaItem) -> String {
        if item.mediaType == .episode, let seriesName = item.seriesName, !seriesName.isEmpty {
            return seriesName
        }
        return item.name
    }

    private static func eyebrow(for item: MediaItem) -> String? {
        if item.mediaType == .episode {
            let seasonEpisode = seasonEpisodeText(for: item)
            if let seasonEpisode, !item.name.isEmpty {
                return "\(seasonEpisode) · \(item.name)"
            }
            return seasonEpisode ?? (item.name.isEmpty ? nil : item.name)
        }

        if let year = item.year {
            return String(year)
        }
        return nil
    }

    private static func seasonEpisodeText(for item: MediaItem) -> String? {
        switch (item.parentIndexNumber, item.indexNumber) {
        case let (.some(season), .some(episode)):
            return "S\(season), E\(episode)"
        case let (.some(season), .none):
            return "S\(season)"
        case let (.none, .some(episode)):
            return "E\(episode)"
        case (.none, .none):
            return nil
        }
    }

    private static func progress(playbackTime: Double, durationSeconds: Double?) -> Double {
        guard let durationSeconds, durationSeconds > 0, playbackTime.isFinite else { return 0 }
        return min(max(playbackTime / durationSeconds, 0), 1)
    }

    private static func formatElapsed(_ seconds: Double) -> String {
        formatTime(max(0, seconds))
    }

    private static func formatRemaining(playbackTime: Double, durationSeconds: Double?) -> String {
        guard let durationSeconds, durationSeconds.isFinite, durationSeconds > 0 else { return "--:--" }
        return "-\(formatTime(max(0, durationSeconds - playbackTime)))"
    }

    private static func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainingSeconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

/// The SampleBuffer player owns its own seek pipeline. Forwarding only to the session's dormant
/// AVPlayer makes the marker disappear without moving the visible video, so seek suggestions must
/// be committed locally as well. Episode chaining remains owned by the playback session.
enum NativePlayerSampleBufferSkipPolicy {
    static func localSeekTarget(for suggestion: PlaybackSkipSuggestion) -> Double? {
        guard case let .seek(to: seconds) = suggestion.target else { return nil }
        return max(0, seconds)
    }
}

struct NativePlayerChromeVisibilityPolicy: Equatable {
    static let autoHideDelaySeconds = 3.5

    enum BackgroundTapAction: Equatable {
        case hide
        case reveal
        case ignore
    }

    static func shouldShowChrome(
        isUserActive: Bool,
        isPaused: Bool,
        isBuffering: Bool,
        showsDiagnostics: Bool,
        hasError: Bool,
        isPinnedForAutomation: Bool = false
    ) -> Bool {
        isPinnedForAutomation || isUserActive || isPaused || isBuffering || showsDiagnostics || hasError
    }

    static func shouldAutoHide(
        isPaused: Bool,
        isBuffering: Bool,
        showsDiagnostics: Bool,
        hasError: Bool,
        isPinnedForAutomation: Bool = false
    ) -> Bool {
        !isPinnedForAutomation && !isPaused && !isBuffering && !showsDiagnostics && !hasError
    }

    static func backgroundTapAction(
        isChromeVisible: Bool,
        hasError: Bool,
        isPinnedForAutomation: Bool
    ) -> BackgroundTapAction {
        guard !hasError, !isPinnedForAutomation else { return .ignore }
        return isChromeVisible ? .hide : .reveal
    }
}

enum NativePlayerTVMenuAction: Equatable {
    case dismissPicker
    case cancelCircularScrub
    case hideChrome
    case exitPlayer
}

enum NativePlayerTVPlayPauseAction: Equatable {
    case consume
    case dispatch
}

enum NativePlayerTVSelectAction: Equatable {
    case showChrome
    case hideChrome
}

/// One platform policy shared by both playback surfaces. Views decide which focused control owns
/// Select, but transport and Menu never fall through to AVKit or a second responder.
struct NativePlayerTVRemoteControlPolicy: Equatable {
    static func menuAction(
        chromeVisible: Bool,
        pickerVisible: Bool,
        isCircularScrubbing: Bool = false
    ) -> NativePlayerTVMenuAction {
        if pickerVisible { return .dismissPicker }
        if isCircularScrubbing { return .cancelCircularScrub }
        if chromeVisible { return .hideChrome }
        return .exitPlayer
    }

    static func playPauseAction(isCircularScrubbing: Bool) -> NativePlayerTVPlayPauseAction {
        isCircularScrubbing ? .consume : .dispatch
    }

    static func selectAction(chromeVisible: Bool) -> NativePlayerTVSelectAction {
        chromeVisible ? .hideChrome : .showChrome
    }

    static func nextFocusReturnToken(after token: UInt) -> UInt {
        token &+ 1
    }
}

enum NativePlayerTVTransportCommand: Equatable {
    case select
    case playPause
    case move(NativePlayerRemoteMoveDirection)
    case openSettings
}

enum NativePlayerTVTimelineNavigation {
    static func command(for direction: NativePlayerRemoteMoveDirection) -> NativePlayerTVTransportCommand {
        direction == .down ? .openSettings : .move(direction)
    }
}

/// The hidden full-screen responder follows the same Down convention as the focused timeline:
/// opening Settings is the action itself, not a two-step "reveal, then press Down again" flow.
enum NativePlayerTVHiddenChromeNavigation {
    static func command(for direction: NativePlayerRemoteMoveDirection) -> NativePlayerTVTransportCommand {
        direction == .down ? .openSettings : .move(direction)
    }
}

/// The sole imperative command router used by both the hidden transport surface and focused
/// timeline. Each input selects exactly one callback; views never fan a press out to AVKit.
struct NativePlayerTVCommandDispatcher {
    let onSelect: () -> Void
    let onPlayPause: () -> Void
    let onMove: (NativePlayerRemoteMoveDirection) -> Void
    let onOpenSettings: () -> Void

    init(
        onSelect: @escaping () -> Void,
        onPlayPause: @escaping () -> Void,
        onMove: @escaping (NativePlayerRemoteMoveDirection) -> Void,
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.onSelect = onSelect
        self.onPlayPause = onPlayPause
        self.onMove = onMove
        self.onOpenSettings = onOpenSettings
    }

    func dispatch(_ command: NativePlayerTVTransportCommand) {
        switch command {
        case .select:
            onSelect()
        case .playPause:
            onPlayPause()
        case let .move(direction):
            onMove(direction)
        case .openSettings:
            onOpenSettings()
        }
    }
}

enum NativePlayerTVChromeFocus: Hashable {
    case timeline
    case video
    case audio
    case subtitles
    case settings

    static func action(_ action: NativePlayerTVChromeAction) -> Self {
        switch action {
        case .video: return .video
        case .audio: return .audio
        case .subtitles: return .subtitles
        case .settings: return .settings
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .timeline: return "native_player_timeline_scrubber"
        case .audio: return NativePlayerTVChromeAction.audio.accessibilityIdentifier
        case .subtitles: return NativePlayerTVChromeAction.subtitles.accessibilityIdentifier
        case .video: return NativePlayerTVChromeAction.video.accessibilityIdentifier
        case .settings: return NativePlayerTVChromeAction.settings.accessibilityIdentifier
        }
    }
}

enum NativePlayerTVChromeFocusGraph {
    static func effectivePreferredFocus(
        _ preferred: NativePlayerTVChromeFocus,
        availableActions: [NativePlayerTVChromeAction]
    ) -> NativePlayerTVChromeFocus {
        if let action = preferred.chromeAction, availableActions.contains(action) {
            return preferred
        }
        if preferred.chromeAction == nil { return preferred }
        return availableActions.first.map(NativePlayerTVChromeFocus.action) ?? .timeline
    }

    static func destination(
        from current: NativePlayerTVChromeFocus,
        direction: NativePlayerRemoteMoveDirection,
        availableActions: [NativePlayerTVChromeAction]
    ) -> NativePlayerTVChromeFocus? {
        if let action = current.chromeAction,
           let index = availableActions.firstIndex(of: action) {
            switch direction {
            case .left:
                let target = max(availableActions.startIndex, index - 1)
                return .action(availableActions[target])
            case .right:
                let target = min(availableActions.index(before: availableActions.endIndex), index + 1)
                return .action(availableActions[target])
            case .down:
                return .timeline
            case .up:
                return nil
            }
        }

        if current == .timeline {
            switch direction {
            case .up:
                return availableActions.first.map(NativePlayerTVChromeFocus.action)
            case .down:
                return nil
            case .left, .right:
                return nil
            }
        }

        return nil
    }

#if os(tvOS)
    static func remoteDirection(from direction: MoveCommandDirection) -> NativePlayerRemoteMoveDirection? {
        switch direction {
        case .left: return .left
        case .right: return .right
        case .up: return .up
        case .down: return .down
        @unknown default: return nil
        }
    }
#endif
}

private extension NativePlayerTVChromeFocus {
    var chromeAction: NativePlayerTVChromeAction? {
        switch self {
        case .video: return .video
        case .subtitles: return .subtitles
        case .audio: return .audio
        case .settings: return .settings
        case .timeline: return nil
        }
    }
}

struct NativePlayerChromeExplicitVisibilityPolicy {
    static func canHideChrome(isTVOS: Bool) -> Bool { isTVOS }
}

struct NativePlayerTVTimelineAccessibility {
    static func value(playbackTime: Double, durationSeconds: Double?) -> String {
        guard let durationSeconds, durationSeconds > 0 else { return "Position unavailable" }
        return "\(Int(playbackTime.rounded())) of \(Int(durationSeconds.rounded())) seconds"
    }
}

struct NativePlayerTVTimelineLabelLayout {
    static func currentCenterX(progress: Double, width: CGFloat) -> CGFloat {
        let clampedProgress = min(max(progress.isFinite ? progress : 0, 0), 1)
        return min(max(48, width * CGFloat(clampedProgress)), max(48, width - 180))
    }
}

struct NativePlayerTVContinueWatchingPolicy {
    static func shouldResume(isPaused: Bool) -> Bool { isPaused }
}

struct NativePlayerTVContinueWatchingTransition: Equatable {
    private var suppressesNextPauseReveal = false

    mutating func beginContinueWatching(isPaused: Bool) {
        suppressesNextPauseReveal = isPaused
    }

    mutating func shouldRevealChromeAfterPauseChange() -> Bool {
        guard suppressesNextPauseReveal else { return true }
        suppressesNextPauseReveal = false
        return false
    }
}

enum NativePlayerRemoteMoveDirection: Equatable {
    case left
    case right
    case up
    case down
}

enum NativePlayerSeekDirection: Equatable {
    case forward
    case backward
}

struct NativePlayerRemoteControlPolicy: Equatable {
    static let rewindSeconds = -10.0
    static let fastForwardSeconds = 30.0
    static let seekCommitDebounceNanoseconds: UInt64 = 280_000_000

    static func relativeSeekSeconds(for direction: NativePlayerRemoteMoveDirection) -> Double? {
        switch direction {
        case .left:
            return rewindSeconds
        case .right:
            return fastForwardSeconds
        case .up, .down:
            return nil
        }
    }

    static func clampedSeekTarget(from baseSeconds: Double, delta: Double, durationSeconds: Double?) -> Double {
        let upperBound = durationSeconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? .greatestFiniteMagnitude
        let target = baseSeconds + delta
        guard target.isFinite else { return 0 }
        return min(max(0, target), upperBound)
    }

    static func seekDirection(from startSeconds: Double, to targetSeconds: Double) -> NativePlayerSeekDirection {
        targetSeconds >= startSeconds ? .forward : .backward
    }

    static func hasReachedSeekTarget(
        reportedSeconds: Double,
        targetSeconds: Double,
        direction: NativePlayerSeekDirection,
        tolerance: Double
    ) -> Bool {
        guard reportedSeconds.isFinite, targetSeconds.isFinite else { return false }
        if abs(reportedSeconds - targetSeconds) <= tolerance { return true }
        switch direction {
        case .forward:
            return reportedSeconds > targetSeconds
        case .backward:
            return reportedSeconds < targetSeconds
        }
    }
}
