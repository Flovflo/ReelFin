import SwiftUI

public enum ReelFinDisplayDensity: String, CaseIterable, Identifiable, Sendable {
    case standard
    case compact
    case dense

    public static let storageKey = "reelfin.display.density"

    public init(rawStoredValue: String) {
        self = Self(rawValue: rawStoredValue) ?? .standard
    }

    public var id: String { rawValue }

    public var settingsLabel: String {
        switch self {
        case .standard:
            return "Standard"
        case .compact:
            return "Compact"
        case .dense:
            return "Dense"
        }
    }

    public var settingsDescription: String {
        switch self {
        case .standard:
            return "Default poster, grid, and detail sizing."
        case .compact:
            return "Shows more items while keeping text close to the default size."
        case .dense:
            return "Prioritizes information density with much smaller artwork and slightly smaller text."
        }
    }

    public var visualScale: CGFloat {
        #if os(tvOS)
        return 1
        #else
        switch self {
        case .standard:
            return 1
        case .compact:
            return 0.90
        case .dense:
            return 0.78
        }
        #endif
    }

    public var textScale: CGFloat {
        #if os(tvOS)
        return 1
        #else
        switch self {
        case .standard:
            return 1
        case .compact:
            return 0.97
        case .dense:
            return 0.92
        }
        #endif
    }

    public var spacingScale: CGFloat {
        #if os(tvOS)
        return 1
        #else
        switch self {
        case .standard:
            return 1
        case .compact:
            return 0.90
        case .dense:
            return 0.82
        }
        #endif
    }

    public func scaledVisualSize(_ value: CGFloat) -> CGFloat {
        value * visualScale
    }

    public func scaledTextSize(_ value: CGFloat) -> CGFloat {
        value * textScale
    }

    public func scaledSpacing(_ value: CGFloat) -> CGFloat {
        value * spacingScale
    }
}

private struct ReelFinDisplayDensityKey: EnvironmentKey {
    static let defaultValue: ReelFinDisplayDensity = .standard
}

public extension EnvironmentValues {
    var reelFinDisplayDensity: ReelFinDisplayDensity {
        get { self[ReelFinDisplayDensityKey.self] }
        set { self[ReelFinDisplayDensityKey.self] = newValue }
    }
}
