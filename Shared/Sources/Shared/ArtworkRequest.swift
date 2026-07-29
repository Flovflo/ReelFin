import Foundation

public struct ArtworkRequest: Hashable, Sendable {
    public let itemID: String
    public let type: JellyfinImageType
    public let profile: ArtworkRequestProfile
    public let allowsSpeculativePrefetch: Bool

    private init(
        itemID: String,
        type: JellyfinImageType,
        profile: ArtworkRequestProfile,
        allowsSpeculativePrefetch: Bool
    ) {
        self.itemID = itemID
        self.type = type
        self.profile = profile
        self.allowsSpeculativePrefetch = allowsSpeculativePrefetch
    }

    public static func make(for item: MediaItem, role: ArtworkRequestRole) -> ArtworkRequest {
        let itemID: String
        if role == .logo {
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
            allowsSpeculativePrefetch: role.allowsSpeculativePrefetch(for: item)
        )
    }
}

public enum ArtworkRequestRole: CaseIterable, Sendable {
    case posterGrid
    case posterRow
    case landscapeRail
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
        case .landscapeRail:
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
            return item.backdropTag == nil ? .primary : .backdrop
        case .logo:
            return .logo
        case .posterGrid, .posterRow, .avatar:
            return .primary
        }
    }

    fileprivate func allowsSpeculativePrefetch(for item: MediaItem) -> Bool {
        guard self != .logo else { return true }

        // Episode requests target their owning series, whose tags are not carried by lightweight
        // episode DTOs. Visible artwork requests are never suppressed by this metadata hint.
        if item.mediaType == .episode, item.parentID != nil {
            return true
        }

        return item.posterTag != nil || item.backdropTag != nil
    }
}
