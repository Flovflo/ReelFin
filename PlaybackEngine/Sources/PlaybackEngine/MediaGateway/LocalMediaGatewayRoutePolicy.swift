import Foundation
import Shared

public enum LocalMediaGatewayRoutePolicy {
    private static let iOSHighBitrateThreshold = 18_000_000
    private static let appleContainers: Set<String> = ["mp4", "m4v", "mov"]

    public static func shouldUseGateway(
        route: PlaybackRoute,
        source: MediaSource?,
        mediaCacheMode: MediaCacheMode,
        isTVOS: Bool,
        resumeSeconds: Double?,
        hasCachedBytes: Bool
    ) -> Bool {
        guard mediaCacheMode != .off, case .directPlay = route else { return false }
        guard isAppleCompatible(source: source) else { return false }

        if isTVOS {
            return true
        }

        guard mediaCacheMode == .automatic else {
            return hasCachedBytes || (resumeSeconds ?? 0) > 0
        }

        let bitrate = source?.bitrate ?? 0
        return hasCachedBytes || (resumeSeconds ?? 0) > 0 || bitrate >= iOSHighBitrateThreshold
    }

    private static func isAppleCompatible(source: MediaSource?) -> Bool {
        guard let source else { return true }
        let container = source.normalizedContainer
        if appleContainers.contains(container) {
            return true
        }
        guard let path = source.filePath?.lowercased() else { return false }
        return appleContainers.contains(URL(fileURLWithPath: path).pathExtension)
    }
}
