import Foundation

public struct ArtworkRequest: Hashable, Sendable {
    public let itemID: String
    public let type: JellyfinImageType
    public let profile: ArtworkRequestProfile

    private init(itemID: String, type: JellyfinImageType, profile: ArtworkRequestProfile) {
        self.itemID = itemID
        self.type = type
        self.profile = profile
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

        return ArtworkRequest(itemID: itemID, type: role.imageType(for: item), profile: role.profile)
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
            return item.backdropTag == nil ? .primary : .backdrop
        case .logo:
            return .logo
        case .posterGrid, .posterRow, .avatar:
            return .primary
        }
    }
}
