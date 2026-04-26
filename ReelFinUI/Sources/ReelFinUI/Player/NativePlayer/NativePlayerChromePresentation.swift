import Foundation
import Shared

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
        hasError: Bool
    ) -> Bool {
        isUserActive || isPaused || isBuffering || showsDiagnostics || hasError
    }

    static func shouldAutoHide(
        isPaused: Bool,
        isBuffering: Bool,
        showsDiagnostics: Bool,
        hasError: Bool
    ) -> Bool {
        !isPaused && !isBuffering && !showsDiagnostics && !hasError
    }
}

enum NativePlayerRemoteMoveDirection {
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
