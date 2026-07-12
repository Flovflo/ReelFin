enum TVDetailPresentationPhase: Equatable, Sendable {
    case idle
    case opening(itemID: String, sourceID: String?)
    case presented(itemID: String, sourceID: String?)
    case closing(itemID: String, sourceID: String?)
}

struct TVDetailPresentationCoordinator: Equatable, Sendable {
    private(set) var phase: TVDetailPresentationPhase = .idle

    var keepsDetailMounted: Bool {
        phase != .idle
    }

    mutating func beginOpening(itemID: String, sourceID: String?) {
        guard phase == .idle else { return }
        phase = .opening(itemID: itemID, sourceID: sourceID)
    }

    mutating func finishOpening() {
        guard case let .opening(itemID, sourceID) = phase else { return }
        phase = .presented(itemID: itemID, sourceID: sourceID)
    }

    mutating func handleBack() -> TVDetailBackResult {
        switch phase {
        case let .opening(itemID, sourceID), let .presented(itemID, sourceID):
            phase = .closing(itemID: itemID, sourceID: sourceID)
            return .beginClosing
        case .closing:
            return .consumedWhileClosing
        case .idle:
            return .allowRoot
        }
    }

    mutating func finishClosing() {
        guard case .closing = phase else { return }
        phase = .idle
    }
}

enum TVDetailBackResult: Equatable, Sendable {
    case beginClosing
    case consumedWhileClosing
    case allowRoot
}

enum TVBackNavigationOwner: Equatable, Sendable {
    case resumeChoice
    case playerPanel
    case player
    case detail
    case root
}

enum TVBackNavigationAction: Equatable, Sendable {
    case cancelResumeChoice
    case closePlayerPanel
    case closePlayer
    case closeDetail
    case allowSystemExit
}

enum TVBackNavigationPolicy {
    static func action(for owner: TVBackNavigationOwner) -> TVBackNavigationAction {
        switch owner {
        case .resumeChoice:
            .cancelResumeChoice
        case .playerPanel:
            .closePlayerPanel
        case .player:
            .closePlayer
        case .detail:
            .closeDetail
        case .root:
            .allowSystemExit
        }
    }
}

enum TVDetailTransitionMetrics {
    static let openingDuration = 0.34
    static let closingDuration = 0.30
    static let reducedMotionDuration = 0.18
}

enum TVDetailPresentationVisualState: Equatable, Sendable {
    case opening
    case presented
    case closing
}

enum TVBackNavigationDebugMarker: String, Equatable, Sendable {
    case detail
    case closing
    case root
}
