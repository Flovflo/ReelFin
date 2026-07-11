import Foundation
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

struct NativePlayerChromeVisibilityPolicy: Equatable {
    static let autoHideDelaySeconds = 3.5

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
}

enum NativePlayerTVMenuAction: Equatable {
    case dismissPicker
    case hideChrome
    case exitPlayer
}

enum NativePlayerTVSelectAction: Equatable {
    case showChrome
    case hideChrome
}

/// One platform policy shared by both playback surfaces. Views decide which focused control owns
/// Select, but transport and Menu never fall through to AVKit or a second responder.
struct NativePlayerTVRemoteControlPolicy: Equatable {
    static func menuAction(chromeVisible: Bool, pickerVisible: Bool) -> NativePlayerTVMenuAction {
        if pickerVisible { return .dismissPicker }
        if chromeVisible { return .hideChrome }
        return .exitPlayer
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
}

/// The sole imperative command router used by both the hidden transport surface and focused
/// timeline. Each input selects exactly one callback; views never fan a press out to AVKit.
struct NativePlayerTVCommandDispatcher {
    let onSelect: () -> Void
    let onPlayPause: () -> Void
    let onMove: (NativePlayerRemoteMoveDirection) -> Void

    func dispatch(_ command: NativePlayerTVTransportCommand) {
        switch command {
        case .select:
            onSelect()
        case .playPause:
            onPlayPause()
        case let .move(direction):
            onMove(direction)
        }
    }
}

enum NativePlayerTVChromeFocus: Hashable {
    case timeline
    case audio
    case subtitles
    case video
    case info
    case insight
    case continueWatching

    static func action(_ action: NativePlayerTVChromeAction) -> Self {
        switch action {
        case .audio: return .audio
        case .subtitles: return .subtitles
        case .video: return .video
        }
    }

    static func utility(_ action: NativePlayerTVChromeUtilityAction) -> Self {
        switch action {
        case .info: return .info
        case .insight: return .insight
        case .continueWatching: return .continueWatching
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .timeline: return "native_player_timeline_scrubber"
        case .audio: return NativePlayerTVChromeAction.audio.accessibilityIdentifier
        case .subtitles: return NativePlayerTVChromeAction.subtitles.accessibilityIdentifier
        case .video: return NativePlayerTVChromeAction.video.accessibilityIdentifier
        case .info: return NativePlayerTVChromeUtilityAction.info.accessibilityIdentifier
        case .insight: return NativePlayerTVChromeUtilityAction.insight.accessibilityIdentifier
        case .continueWatching: return NativePlayerTVChromeUtilityAction.continueWatching.accessibilityIdentifier
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
                return .info
            case .left, .right:
                return nil
            }
        }

        if let utility = current.utilityAction,
           let index = NativePlayerTVChromeUtilityAction.allCases.firstIndex(of: utility) {
            switch direction {
            case .left:
                let target = max(NativePlayerTVChromeUtilityAction.allCases.startIndex, index - 1)
                return .utility(NativePlayerTVChromeUtilityAction.allCases[target])
            case .right:
                let target = min(
                    NativePlayerTVChromeUtilityAction.allCases.index(before: NativePlayerTVChromeUtilityAction.allCases.endIndex),
                    index + 1
                )
                return .utility(NativePlayerTVChromeUtilityAction.allCases[target])
            case .up:
                return .timeline
            case .down:
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
        case .subtitles: return .subtitles
        case .audio: return .audio
        case .video: return .video
        case .timeline, .info, .insight, .continueWatching: return nil
        }
    }

    var utilityAction: NativePlayerTVChromeUtilityAction? {
        switch self {
        case .info: return .info
        case .insight: return .insight
        case .continueWatching: return .continueWatching
        case .timeline, .subtitles, .audio, .video: return nil
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
