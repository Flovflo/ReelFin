import Foundation

public enum NativeVLCClassRouteViolation: Equatable, LocalizedError, Sendable {
    case legacyPlaybackCoordinator
    case avPlayerItemCreation
    case avPlayerViewControllerSurface
    case forceH264TranscodeProfile
    case serverTranscodeBlockedByConfig
    case hlsPlaylistURL(String)
    case forbiddenTranscodeQueryItem(name: String, value: String?)

    public var errorDescription: String? {
        switch self {
        case .legacyPlaybackCoordinator:
            return "Native VLC-class mode must not route through the legacy playback coordinator."
        case .avPlayerItemCreation:
            return "Native VLC-class mode must not create AVPlayerItem."
        case .avPlayerViewControllerSurface:
            return "Native VLC-class mode must not use AVPlayerViewController."
        case .forceH264TranscodeProfile:
            return "Native VLC-class mode must not select forceH264Transcode."
        case .serverTranscodeBlockedByConfig:
            return "Native VLC-class mode blocks Jellyfin server transcode because allowServerTranscodeFallback=false."
        case .hlsPlaylistURL(let path):
            return "Native VLC-class mode must not use Jellyfin HLS playlist URL: \(path)"
        case .forbiddenTranscodeQueryItem(let name, let value):
            if let value {
                return "Native VLC-class mode must not use transcode query item \(name)=\(value)."
            }
            return "Native VLC-class mode must not use transcode query item \(name)."
        }
    }
}

public struct NativeVLCClassRouteProof: Equatable, Sendable {
    public var usedLegacyPlaybackCoordinator: Bool
    public var createdAVPlayerItem: Bool
    public var usedAVPlayerViewController: Bool
    public var transcodeProfile: String?
    public var selectedURL: URL?

    public init(
        usedLegacyPlaybackCoordinator: Bool = false,
        createdAVPlayerItem: Bool = false,
        usedAVPlayerViewController: Bool = false,
        transcodeProfile: String? = nil,
        selectedURL: URL? = nil
    ) {
        self.usedLegacyPlaybackCoordinator = usedLegacyPlaybackCoordinator
        self.createdAVPlayerItem = createdAVPlayerItem
        self.usedAVPlayerViewController = usedAVPlayerViewController
        self.transcodeProfile = transcodeProfile
        self.selectedURL = selectedURL
    }
}

public enum NativeVLCClassRouteGuard {
    public static func validate(_ proof: NativeVLCClassRouteProof) -> [NativeVLCClassRouteViolation] {
        var violations: [NativeVLCClassRouteViolation] = []
        if proof.usedLegacyPlaybackCoordinator { violations.append(.legacyPlaybackCoordinator) }
        if proof.createdAVPlayerItem { violations.append(.avPlayerItemCreation) }
        if proof.usedAVPlayerViewController { violations.append(.avPlayerViewControllerSurface) }
        if proof.transcodeProfile?.caseInsensitiveCompare("forceH264Transcode") == .orderedSame {
            violations.append(.forceH264TranscodeProfile)
        }
        if let url = proof.selectedURL {
            violations.append(contentsOf: validateOriginalPlaybackURL(url))
        }
        return violations
    }

    public static func validateOriginalPlaybackURL(_ url: URL) -> [NativeVLCClassRouteViolation] {
        var violations: [NativeVLCClassRouteViolation] = []
        let lowerPath = url.path.lowercased()
        if lowerPath.hasSuffix(".m3u8")
            || lowerPath.contains("/master.m3u8")
            || lowerPath.contains("/main.m3u8") {
            violations.append(.hlsPlaylistURL(url.path))
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return violations
        }
        for item in components.queryItems ?? [] {
            if let violation = violation(forQueryName: item.name, value: item.value) {
                violations.append(violation)
            }
        }
        return violations
    }

    public static func firstViolationDescription(for proof: NativeVLCClassRouteProof) -> String? {
        validate(proof).first?.localizedDescription
    }

    private static func violation(forQueryName name: String, value: String?) -> NativeVLCClassRouteViolation? {
        let loweredName = name.lowercased()
        let loweredValue = value?.lowercased()
        switch loweredName {
        case "transcodereasons":
            return .forbiddenTranscodeQueryItem(name: name, value: value)
        case "videocodec" where queryValueContains(loweredValue, token: "h264"):
            return .forbiddenTranscodeQueryItem(name: name, value: value)
        case "audiocodec" where queryValueContains(loweredValue, token: "aac"):
            return .forbiddenTranscodeQueryItem(name: name, value: value)
        case "allowvideostreamcopy" where loweredValue == "false":
            return .forbiddenTranscodeQueryItem(name: name, value: value)
        case "allowaudiostreamcopy" where loweredValue == "false":
            return .forbiddenTranscodeQueryItem(name: name, value: value)
        case "requireavc" where loweredValue == "true":
            return .forbiddenTranscodeQueryItem(name: name, value: value)
        default:
            return nil
        }
    }

    private static func queryValueContains(_ value: String?, token: String) -> Bool {
        guard let value else { return false }
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { $0.caseInsensitiveCompare(token) == .orderedSame }
    }
}
