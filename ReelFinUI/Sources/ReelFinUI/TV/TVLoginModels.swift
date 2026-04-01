#if os(tvOS)
import SwiftUI

enum TVLoginPhase {
    case landing
    case server
    case credentials
    case submitting
    case quickConnect
    case success
}

enum TVLoginFocus: Hashable {
    case primary
    case secondary
    case tertiary
    case textA
    case textB
}

enum TVLoginSignInPath {
    case quickConnect
    case credentials

    var alternate: Self {
        switch self {
        case .quickConnect:
            .credentials
        case .credentials:
            .quickConnect
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .quickConnect:
            "Get Code"
        case .credentials:
            "Continue"
        }
    }

    var alternateActionTitle: String {
        switch self {
        case .quickConnect:
            "Use Password"
        case .credentials:
            "Quick Connect"
        }
    }

    var primaryActionSymbol: String {
        switch self {
        case .quickConnect:
            "qrcode"
        case .credentials:
            "arrow.right"
        }
    }

    var alternateActionSymbol: String {
        switch self {
        case .quickConnect:
            "keyboard"
        case .credentials:
            "qrcode"
        }
    }
}

struct TVLoginLayoutMetrics {
    let heroWidth: CGFloat
    let heroHeight: CGFloat
    let panelWidth: CGFloat
    let panelHorizontalPadding: CGFloat
    let panelVerticalPadding: CGFloat
    let outerHorizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
    let panelSpacing: CGFloat
    let landingButtonWidth: CGFloat

    init(size: CGSize, phase: TVLoginPhase) {
        heroWidth = min(size.width * 0.86, 1_260)
        heroHeight = min(max(size.height * 0.54, 430), 590)
        panelWidth = switch phase {
        case .landing:
            min(size.width - 180, 1_040)
        case .success:
            min(size.width - 200, 760)
        default:
            min(size.width - 180, 860)
        }
        panelHorizontalPadding = phase == .landing ? 48 : 34
        panelVerticalPadding = phase == .landing ? 38 : 30
        outerHorizontalPadding = 64
        topPadding = 42
        bottomPadding = 54
        panelSpacing = phase == .landing ? 40 : 26
        landingButtonWidth = min(max(size.width * 0.25, 320), 390)
    }
}
#endif
