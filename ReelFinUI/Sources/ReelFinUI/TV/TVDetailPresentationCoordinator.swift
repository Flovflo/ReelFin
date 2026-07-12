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

enum TVHomeDetailPresentationOrigin: Equatable, Sendable {
    case featured
    case row(id: String)
}

struct TVHomeDetailPresentationContext: Equatable, Sendable {
    let origin: TVHomeDetailPresentationOrigin
    let presentedItemIDs: [String]
}

struct TVHomeDetailReturnTarget: Equatable, Sendable {
    let origin: TVHomeDetailPresentationOrigin
    let displayedItemID: String
    let itemID: String

    var focusTargetID: String? {
        guard case let .row(rowID) = origin else { return nil }
        return HomeCardTransitionSource.id(rowID: rowID, itemID: itemID)
    }
}

enum TVHomeDetailReturnTargetResolver {
    static func resolve(
        context: TVHomeDetailPresentationContext,
        displayedItemID: String,
        featuredItemIDs: [String],
        rowItemIDsByID: [String: [String]]
    ) -> TVHomeDetailReturnTarget? {
        let currentRailItemIDs: [String]
        switch context.origin {
        case .featured:
            currentRailItemIDs = featuredItemIDs
        case let .row(rowID):
            guard let rowItemIDs = rowItemIDsByID[rowID] else { return nil }
            currentRailItemIDs = rowItemIDs
        }

        guard let resolvedItemID = resolvedItemID(
            displayedItemID: displayedItemID,
            presentedItemIDs: context.presentedItemIDs,
            currentRailItemIDs: currentRailItemIDs
        ) else { return nil }

        return TVHomeDetailReturnTarget(
            origin: context.origin,
            displayedItemID: displayedItemID,
            itemID: resolvedItemID
        )
    }

    private static func resolvedItemID(
        displayedItemID: String,
        presentedItemIDs: [String],
        currentRailItemIDs: [String]
    ) -> String? {
        guard !currentRailItemIDs.isEmpty else { return nil }
        if currentRailItemIDs.contains(displayedItemID) {
            return displayedItemID
        }

        guard let displayedIndex = presentedItemIDs.firstIndex(of: displayedItemID) else {
            return currentRailItemIDs.first
        }

        let presentedIndexByItemID = Dictionary(
            uniqueKeysWithValues: presentedItemIDs.enumerated().map { ($1, $0) }
        )
        return currentRailItemIDs
            .compactMap { itemID -> (itemID: String, index: Int, distance: Int)? in
                guard let index = presentedIndexByItemID[itemID] else { return nil }
                return (itemID, index, abs(index - displayedIndex))
            }
            .min { lhs, rhs in
                if lhs.distance != rhs.distance {
                    return lhs.distance < rhs.distance
                }
                return lhs.index < rhs.index
            }?
            .itemID
    }
}

enum TVDetailDismissalRouter {
    static func request(
        explicit: (() -> Void)?,
        fallback: () -> Void
    ) {
        if let explicit {
            explicit()
        } else {
            fallback()
        }
    }
}

struct TVHomeFocusHandoffRequest: Equatable, Sendable {
    let generation: UInt
    let targetID: String
}

struct TVHomeFocusHandoffCoordinator: Equatable, Sendable {
    private var generation: UInt = 0
    private var activeGeneration: UInt?

    var hasPendingRequest: Bool {
        activeGeneration != nil
    }

    mutating func begin(targetID: String) -> TVHomeFocusHandoffRequest {
        generation &+= 1
        activeGeneration = generation
        return TVHomeFocusHandoffRequest(generation: generation, targetID: targetID)
    }

    mutating func cancel() {
        generation &+= 1
        activeGeneration = nil
    }

    mutating func userFocusDidChange() {
        cancel()
    }

    func owns(_ request: TVHomeFocusHandoffRequest) -> Bool {
        generation == request.generation && activeGeneration == request.generation
    }

    mutating func consume(_ request: TVHomeFocusHandoffRequest) -> String? {
        guard owns(request) else { return nil }
        activeGeneration = nil
        generation &+= 1
        return request.targetID
    }
}
