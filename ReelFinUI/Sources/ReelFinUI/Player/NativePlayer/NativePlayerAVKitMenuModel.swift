import Foundation
import Shared

enum NativePlayerAVKitMenuPage: Equatable {
    case audio
    case subtitlesRoot
    case subtitleLanguages
    case subtitleStyles

    var rowIDs: [NativePlayerAVKitMenuRowID] {
        switch self {
        case .subtitlesRoot:
            return [.subtitleOn, .subtitleOff, .subtitleLanguage, .subtitleStyle]
        default:
            return []
        }
    }
}

enum NativePlayerAVKitMenuRowID: Hashable {
    case audio(String)
    case subtitleOn
    case subtitleOff
    case subtitleLanguage
    case subtitleStyle
    case subtitleTrack(String)
    case style(SubtitleBackgroundStyle)
}

enum NativePlayerSubtitleMenuPolicy {
    static func enabledTrackID(
        options: [PlaybackTrackOption],
        lastEnabledID: String?
    ) -> String? {
        let real = options.filter { $0.trackID != nil }

        if let lastEnabledID,
           real.contains(where: { $0.trackID == lastEnabledID }) {
            return lastEnabledID
        }
        if let selected = real.first(where: \.isSelected)?.trackID {
            return selected
        }
        if let forced = real.first(where: {
            ($0.badge ?? "").localizedCaseInsensitiveContains("forc")
        })?.trackID {
            return forced
        }
        return real.first?.trackID
    }
}

enum NativePlayerAVKitMenuFocusPolicy {
    static func move(
        from current: NativePlayerAVKitMenuRowID,
        delta: Int,
        rows: [NativePlayerAVKitMenuRowID]
    ) -> NativePlayerAVKitMenuRowID {
        guard let index = rows.firstIndex(of: current), !rows.isEmpty else {
            return rows.first ?? current
        }
        let boundedDelta: Int
        if delta >= 0 {
            boundedDelta = min(delta, rows.count - 1 - index)
        } else {
            boundedDelta = max(delta, -index)
        }
        return rows[index + boundedDelta]
    }

    static func parent(
        of page: NativePlayerAVKitMenuPage
    ) -> NativePlayerAVKitMenuPage? {
        switch page {
        case .subtitleLanguages, .subtitleStyles:
            return .subtitlesRoot
        case .audio, .subtitlesRoot:
            return nil
        }
    }
}
