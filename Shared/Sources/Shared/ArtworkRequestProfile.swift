import Foundation

public enum ArtworkRequestProfile: String, CaseIterable, Sendable {
    case posterGrid
    case posterRow
    case landscapeRail
    case heroBackdropLow
    case heroBackdropHigh
    case avatar
    case logo

    public var width: Int {
        switch self {
        case .posterGrid:
            return 420
        case .posterRow:
            return 360
        case .landscapeRail:
            return 560
        case .heroBackdropLow:
            return 960
        case .heroBackdropHigh:
            return 1_920
        case .avatar:
            return 240
        case .logo:
            return 900
        }
    }

    public var quality: Int {
        switch self {
        case .posterGrid:
            return 84
        case .posterRow:
            return 82
        case .landscapeRail:
            return 82
        case .heroBackdropLow:
            return 68
        case .heroBackdropHigh:
            return 82
        case .avatar:
            return 82
        case .logo:
            return 92
        }
    }
}
