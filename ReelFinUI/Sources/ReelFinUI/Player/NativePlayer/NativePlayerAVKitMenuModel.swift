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
        if let defaultTrack = real.first(where: {
            let label = normalizedLabel(for: $0)
            return label.localizedCaseInsensitiveContains("default")
                || label.localizedCaseInsensitiveContains("defaut")
        })?.trackID {
            return defaultTrack
        }
        if let forced = real.first(where: {
            normalizedLabel(for: $0).localizedCaseInsensitiveContains("forc")
        })?.trackID {
            return forced
        }
        return real.first?.trackID
    }

    private static func normalizedLabel(for option: PlaybackTrackOption) -> String {
        "\(option.title) \(option.badge ?? "")"
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

/// Player-route state that outlives the transient menu view. `nil` means Off and intentionally
/// leaves the last confirmed enabled choice intact for Off → dismiss → reopen → On.
struct NativePlayerSubtitleSelectionMemory: Equatable {
    private(set) var lastEnabledID: String?

    mutating func confirm(trackID: String?) {
        guard let trackID else { return }
        lastEnabledID = trackID
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
