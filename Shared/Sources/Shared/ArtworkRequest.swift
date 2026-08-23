import Foundation

public struct ArtworkRequest: Hashable, Sendable {
    public let itemID: String
    public let type: JellyfinImageType
    public let profile: ArtworkRequestProfile
    public let allowsSpeculativePrefetch: Bool
    public let shouldProbeLocal: Bool

    private init(
        itemID: String,
        type: JellyfinImageType,
        profile: ArtworkRequestProfile,
        allowsSpeculativePrefetch: Bool,
        shouldProbeLocal: Bool
    ) {
        self.itemID = itemID
        self.type = type
        self.profile = profile
        self.allowsSpeculativePrefetch = allowsSpeculativePrefetch
        self.shouldProbeLocal = shouldProbeLocal
    }

    public static func make(for item: MediaItem, role: ArtworkRequestRole) -> ArtworkRequest {
        let itemID: String
        if role == .logo || role == .episodeStill {
            itemID = item.id
        } else if item.mediaType == .episode {
            itemID = item.parentID ?? item.id
        } else {
            itemID = item.id
        }

        return ArtworkRequest(
            itemID: itemID,
            type: role.imageType(for: item),
            profile: role.profile,
            allowsSpeculativePrefetch: role.allowsSpeculativePrefetch(for: item),
            shouldProbeLocal: role.shouldProbeLocal(for: item)
        )
    }
}

public enum ArtworkRequestRole: CaseIterable, Sendable {
    case posterGrid
    case posterRow
    case landscapeRail
    case episodeStill
    case heroLow
    case heroHigh
    case logo
    case avatar

    public var profile: ArtworkRequestProfile {
        switch self {
        case .posterGrid:
            return .posterGrid
        case .posterRow:
            return .posterRow
        case .landscapeRail, .episodeStill:
            return .landscapeRail
        case .heroLow:
            return .heroBackdropLow
        case .heroHigh:
            return .heroBackdropHigh
        case .logo:
            return .logo
        case .avatar:
            return .avatar
        }
    }

    fileprivate func imageType(for item: MediaItem) -> JellyfinImageType {
        switch self {
        case .landscapeRail, .heroLow, .heroHigh:
            if item.mediaType == .episode, item.parentID != nil {
                return .backdrop
            }
            if item.backdropTag != nil {
                return .backdrop
            }
            if item.posterTag != nil {
                return .primary
            }
            // With no local hints, preserve the requested landscape shape for the read-only
            // provider fallback instead of stretching a portrait poster across the hero.
            return .backdrop
        case .logo:
            return .logo
        case .posterGrid, .posterRow, .episodeStill, .avatar:
            return .primary
        }
    }

    fileprivate func allowsSpeculativePrefetch(for item: MediaItem) -> Bool {
        guard self != .logo else { return true }

        // Person credits frequently omit PrimaryImageTag even though Jellyfin serves a portrait.
        // A bounded avatar prefetch is therefore authoritative, just like the visible request.
        if self == .avatar {
            return true
        }

        // Episode requests target their owning series, whose tags are not carried by lightweight
        // episode DTOs. Visible artwork requests are never suppressed by this metadata hint.
        if self == .episodeStill, item.mediaType == .episode {
            return true
        }

        if item.mediaType == .episode, item.parentID != nil {
            return true
        }

        return item.posterTag != nil || item.backdropTag != nil
    }

    fileprivate func shouldProbeLocal(for item: MediaItem) -> Bool {
        if self == .avatar {
            return true
        }

        // Lightweight episode payloads do not reliably carry every series image tag.
        if self == .episodeStill, item.mediaType == .episode {
            return true
        }

        if item.mediaType == .episode, item.parentID != nil {
            return true
        }

        // The compact domain model has no logo tag, so logo availability remains unknown.
        if self == .logo {
            return true
        }

        return item.posterTag != nil || item.backdropTag != nil
    }
}
