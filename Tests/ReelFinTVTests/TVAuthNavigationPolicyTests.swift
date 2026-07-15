import XCTest
import Shared
@testable import ReelFinUI

final class TVAuthNavigationPolicyTests: XCTestCase {
    func testOnboardingUsesFourDistinctUncroppedProductScreensWithoutMotion() {
        let items = TVOnboardingContent.items

        XCTAssertEqual(
            items.map(\.screenshotName),
            [
                "reelfin-tv-onboarding-home-live.png",
                "reelfin-tv-onboarding-library-live.png",
                "reelfin-tv-onboarding-detail-live.png",
                "reelfin-tv-onboarding-player-live.png"
            ]
        )
        XCTAssertEqual(Set(items.map(\.screenshotName)).count, items.count)
        XCTAssertEqual(TVOnboardingMotionPolicy.configuration(reduceMotion: false).pageOffset, 28)
    }

    func testOnboardingLayoutFitsFullHDAndHDActionSafeAreas() {
        for canvas in [CGSize(width: 1_920, height: 1_080), CGSize(width: 1_280, height: 720)] {
            let metrics = TVOnboardingLayoutPolicy.metrics(for: canvas)

            XCTAssertGreaterThanOrEqual(metrics.safeFrame.minX, 80)
            XCTAssertGreaterThanOrEqual(metrics.safeFrame.minY, 60)
            XCTAssertLessThanOrEqual(metrics.safeFrame.maxX, canvas.width - 80)
            XCTAssertLessThanOrEqual(metrics.safeFrame.maxY, canvas.height - 60)
            XCTAssertLessThanOrEqual(
                metrics.copyMaximumWidth + metrics.copyToActionsSpacing + metrics.actionRailWidth,
                metrics.safeFrame.width
            )
            XCTAssertTrue(metrics.safeFrame.contains(metrics.heroFrame))
            XCTAssertEqual(metrics.heroFrame.width / metrics.heroFrame.height, 16.0 / 9.0, accuracy: 0.001)
        }

        XCTAssertFalse(TVOnboardingLayoutPolicy.metrics(for: CGSize(width: 1_920, height: 1_080)).stacksActions)
        XCTAssertTrue(TVOnboardingLayoutPolicy.metrics(for: CGSize(width: 1_280, height: 720)).stacksActions)
    }

    func testOnboardingHeroNeverIntersectsCopyOrActionsAtSupportedTVSizes() {
        let canvases = [
            CGSize(width: 1_920, height: 1_080),
            CGSize(width: 1_280, height: 720)
        ]

        for item in TVOnboardingContent.items {
            for canvas in canvases {
                let metrics = TVOnboardingLayoutPolicy.metrics(for: canvas)

                XCTAssertFalse(
                    metrics.heroFrame.intersects(metrics.copyFrame),
                    "Page \(item.id + 1) hero \(metrics.heroFrame) intersects copy \(metrics.copyFrame) at \(canvas)."
                )
                XCTAssertFalse(
                    metrics.heroFrame.intersects(metrics.actionsFrame),
                    "Page \(item.id + 1) hero \(metrics.heroFrame) intersects actions \(metrics.actionsFrame) at \(canvas)."
                )
            }
        }
    }

    func testReducedMotionDisablesPageOffset() {
        let reduced = TVOnboardingMotionPolicy.configuration(reduceMotion: true)

        XCTAssertEqual(reduced.pageOffset, 0)
    }

    func testDeckClampsInitialPageAndCompletesOnlyAtLastPage() {
        var deck = TVOnboardingDeckState(initialIndex: 99, count: 4)
        XCTAssertEqual(deck.index, 3)
        XCTAssertEqual(deck.advance(), .completed)
    }

    func testDeckAdvancesAndRetreatsWithoutCrossingBounds() {
        var deck = TVOnboardingDeckState(initialIndex: 0, count: 4)
        XCTAssertEqual(deck.advance(), .advanced)
        XCTAssertEqual(deck.index, 1)
        XCTAssertTrue(deck.retreat())
        XCTAssertEqual(deck.index, 0)
        XCTAssertFalse(deck.retreat())
    }

    func testEveryInteractiveLoginPhaseHasRouteSpecificPreferredFocus() {
        XCTAssertEqual(TVLoginNavigationPolicy.preferredFocus(for: .landing), .landingQuickConnect)
        XCTAssertEqual(TVLoginNavigationPolicy.preferredFocus(for: .server), .serverAddress)
        XCTAssertEqual(TVLoginNavigationPolicy.preferredFocus(for: .credentials), .credentialsUsername)
        XCTAssertEqual(TVLoginNavigationPolicy.preferredFocus(for: .quickConnect), .quickConnectUsePassword)
        XCTAssertNil(TVLoginNavigationPolicy.preferredFocus(for: .submitting))
        XCTAssertNil(TVLoginNavigationPolicy.preferredFocus(for: .success))
    }

    func testBackDestinationsRespectQuickConnectOrigin() {
        XCTAssertEqual(TVLoginNavigationPolicy.backDestination(from: .server, quickConnectOrigin: .landing), .landing)
        XCTAssertEqual(TVLoginNavigationPolicy.backDestination(from: .credentials, quickConnectOrigin: .landing), .server)
        XCTAssertEqual(TVLoginNavigationPolicy.backDestination(from: .quickConnect, quickConnectOrigin: .landing), .landing)
        XCTAssertEqual(TVLoginNavigationPolicy.backDestination(from: .quickConnect, quickConnectOrigin: .server), .server)
        XCTAssertNil(TVLoginNavigationPolicy.backDestination(from: .landing, quickConnectOrigin: .landing))
    }
}

@MainActor
final class TVLoginAsyncOwnershipTests: XCTestCase {
    func testCancelledConnectionDoesNotCommitFailureOrClearValidatedServer() async {
        let gate = TVLoginAsyncRequestGate()
        let apiClient = MockJellyfinAPIClient(
            authenticated: false,
            testConnectionOverride: { _ in
                try await gate.suspendConnectionRequest()
            }
        )
        let dependencies = ReelFinPreviewFactory.dependencies(
            authenticated: false,
            apiClient: apiClient
        )
        let viewModel = LoginViewModel(dependencies: dependencies)
        let originalURL = viewModel.validatedServerURL

        let request = Task { await viewModel.testConnection() }
        await gate.waitForConnectionRequestCount(1)

        request.cancel()
        await gate.failConnectionRequest(0, error: CancellationError())

        let requestSucceeded = await request.value
        XCTAssertFalse(requestSucceeded)
        XCTAssertNil(viewModel.serverErrorMessage)
        XCTAssertEqual(viewModel.validatedServerURL, originalURL)
    }

    func testOlderConnectionFailureCannotOverwriteNewerSuccess() async {
        let gate = TVLoginAsyncRequestGate()
        let apiClient = MockJellyfinAPIClient(
            authenticated: false,
            testConnectionOverride: { _ in
                try await gate.suspendConnectionRequest()
            }
        )
        let dependencies = ReelFinPreviewFactory.dependencies(
            authenticated: false,
            apiClient: apiClient
        )
        let viewModel = LoginViewModel(dependencies: dependencies)

        viewModel.serverURLText = "https://old.example"
        viewModel.serverURLDidChange()
        let oldRequest = Task { await viewModel.testConnection() }
        await gate.waitForConnectionRequestCount(1)

        viewModel.serverURLText = "https://new.example"
        viewModel.serverURLDidChange()
        let newRequest = Task { await viewModel.testConnection() }
        await gate.waitForConnectionRequestCount(2)

        await gate.resolveConnectionRequest(1)
        let newRequestSucceeded = await newRequest.value
        XCTAssertTrue(newRequestSucceeded)
        XCTAssertEqual(viewModel.validatedServerURL, URL(string: "https://new.example"))

        await gate.failConnectionRequest(0, error: AppError.invalidServerURL)
        let oldRequestSucceeded = await oldRequest.value
        XCTAssertFalse(oldRequestSucceeded)
        XCTAssertNil(viewModel.serverErrorMessage)
        XCTAssertEqual(viewModel.validatedServerURL, URL(string: "https://new.example"))
    }

    func testEditingServerWhileConnectionIsInFlightInvalidatesCompletion() async {
        let gate = TVLoginAsyncRequestGate()
        let apiClient = MockJellyfinAPIClient(
            authenticated: false,
            testConnectionOverride: { _ in
                try await gate.suspendConnectionRequest()
            }
        )
        let dependencies = ReelFinPreviewFactory.dependencies(
            authenticated: false,
            apiClient: apiClient
        )
        let viewModel = LoginViewModel(dependencies: dependencies)

        viewModel.serverURLText = "https://old.example"
        viewModel.serverURLDidChange()
        let request = Task { await viewModel.testConnection() }
        await gate.waitForConnectionRequestCount(1)

        viewModel.serverURLText = "https://new.example"
        await gate.resolveConnectionRequest(0)

        let requestSucceeded = await request.value
        XCTAssertFalse(requestSucceeded)
        XCTAssertFalse(viewModel.isTestingConnection)
        XCTAssertNil(viewModel.validatedServerURL)
        XCTAssertNil(viewModel.serverMessage)
        XCTAssertNil(viewModel.serverErrorMessage)
    }

    func testEditingServerWhileConnectionIsInFlightSuppressesOldFailure() async {
        let gate = TVLoginAsyncRequestGate()
        let apiClient = MockJellyfinAPIClient(
            authenticated: false,
            testConnectionOverride: { _ in
                try await gate.suspendConnectionRequest()
            }
        )
        let dependencies = ReelFinPreviewFactory.dependencies(
            authenticated: false,
            apiClient: apiClient
        )
        let viewModel = LoginViewModel(dependencies: dependencies)

        viewModel.serverURLText = "https://old.example"
        viewModel.serverURLDidChange()
        let request = Task { await viewModel.testConnection() }
        await gate.waitForConnectionRequestCount(1)

        viewModel.serverURLText = "https://new.example"
        await gate.failConnectionRequest(0, error: AppError.network("Old server failed"))

        let requestSucceeded = await request.value
        XCTAssertFalse(requestSucceeded)
        XCTAssertFalse(viewModel.isTestingConnection)
        XCTAssertNil(viewModel.validatedServerURL)
        XCTAssertNil(viewModel.serverMessage)
        XCTAssertNil(viewModel.serverErrorMessage)
    }

    func testExplicitConnectionCancellationImmediatelyReleasesLoadingAndSuppressesCompletion() async {
        let gate = TVLoginAsyncRequestGate()
        let apiClient = MockJellyfinAPIClient(
            authenticated: false,
            testConnectionOverride: { _ in
                try await gate.suspendConnectionRequest()
            }
        )
        let dependencies = ReelFinPreviewFactory.dependencies(
            authenticated: false,
            apiClient: apiClient
        )
        let viewModel = LoginViewModel(dependencies: dependencies)
        viewModel.serverURLText = "https://old.example"
        viewModel.serverURLDidChange()

        let request = Task { await viewModel.testConnection() }
        await gate.waitForConnectionRequestCount(1)
        XCTAssertTrue(viewModel.isTestingConnection)

        viewModel.cancelConnectionTest()

        XCTAssertFalse(viewModel.isTestingConnection)
        XCTAssertTrue(viewModel.canAdvanceFromServer)
        await gate.resolveConnectionRequest(0)
        let requestSucceeded = await request.value
        XCTAssertFalse(requestSucceeded)
        XCTAssertNil(viewModel.validatedServerURL)
        XCTAssertNil(viewModel.serverMessage)
        XCTAssertNil(viewModel.serverErrorMessage)
    }

    func testConnectionTaskCancelledBeforeStartDoesNotReachAPI() async {
        let apiClient = MockJellyfinAPIClient(authenticated: false)
        let dependencies = ReelFinPreviewFactory.dependencies(
            authenticated: false,
            apiClient: apiClient
        )
        let viewModel = LoginViewModel(dependencies: dependencies)

        let request = Task { await viewModel.testConnection() }
        request.cancel()

        let requestSucceeded = await request.value
        XCTAssertFalse(requestSucceeded)
        XCTAssertEqual(apiClient.testConnectionCallCount, 0)
        XCTAssertFalse(viewModel.isTestingConnection)
    }

    func testCancelledQuickConnectCompletionCannotOverwriteNewRequest() async {
        let gate = TVLoginAsyncRequestGate()
        let apiClient = MockJellyfinAPIClient(
            authenticated: false,
            initiateQuickConnectOverride: { _ in
                try await gate.suspendQuickConnectRequest()
            }
        )
        let dependencies = ReelFinPreviewFactory.dependencies(
            authenticated: false,
            apiClient: apiClient
        )
        let viewModel = QuickConnectViewModel(dependencies: dependencies)
        let serverURL = URL(string: "https://demo.reelfin.app")!

        let oldRequest = Task { await viewModel.initiate(serverURL: serverURL) }
        await gate.waitForQuickConnectRequestCount(1)

        viewModel.cancel()
        oldRequest.cancel()

        let newRequest = Task { await viewModel.initiate(serverURL: serverURL) }
        await gate.waitForQuickConnectRequestCount(2)
        await gate.resolveQuickConnectRequest(
            1,
            state: QuickConnectState(code: "2222", secret: "new-secret")
        )
        await newRequest.value
        XCTAssertEqual(approvalCode(in: viewModel.state), "2222")

        await gate.resolveQuickConnectRequest(
            0,
            state: QuickConnectState(code: "1111", secret: "old-secret")
        )
        await oldRequest.value

        XCTAssertEqual(approvalCode(in: viewModel.state), "2222")
        viewModel.cancel()
    }

    func testCancelledQuickConnectPollCannotAuthenticateOverNewRequest() async {
        let gate = TVLoginAsyncRequestGate()
        let apiClient = MockJellyfinAPIClient(
            authenticated: false,
            pollQuickConnectOverride: { _ in
                try await gate.suspendQuickConnectPoll()
            }
        )
        let dependencies = ReelFinPreviewFactory.dependencies(
            authenticated: false,
            apiClient: apiClient
        )
        let viewModel = QuickConnectViewModel(dependencies: dependencies)
        let serverURL = URL(string: "https://demo.reelfin.app")!
        let oldAuthentication = expectation(description: "Old poll must not authenticate")
        oldAuthentication.isInverted = true
        let newAuthentication = expectation(description: "New poll authenticates")
        var authenticatedUsernames: [String] = []
        viewModel.onAuthenticated = { session in
            authenticatedUsernames.append(session.username)
            if session.username == "old" {
                oldAuthentication.fulfill()
            } else if session.username == "new" {
                newAuthentication.fulfill()
            }
        }

        await viewModel.initiate(serverURL: serverURL)
        await gate.waitForQuickConnectPollCount(1)

        viewModel.cancel()
        await viewModel.initiate(serverURL: serverURL)
        await gate.waitForQuickConnectPollCount(2)

        await gate.resolveQuickConnectPoll(
            0,
            session: UserSession(userID: "old", username: "old", token: "old-token")
        )
        await gate.resolveQuickConnectPoll(
            1,
            session: UserSession(userID: "new", username: "new", token: "new-token")
        )

        await fulfillment(of: [newAuthentication, oldAuthentication], timeout: 0.5)
        XCTAssertEqual(authenticatedUsernames, ["new"])
        viewModel.cancel()
    }

    private func approvalCode(in state: QuickConnectViewModel.State) -> String? {
        guard case let .awaitingApproval(code) = state else { return nil }
        return code
    }
}

private actor TVLoginAsyncRequestGate {
    private var connectionRequestCount = 0
    private var connectionRequests: [Int: CheckedContinuation<Void, Error>] = [:]
    private var connectionWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    private var quickConnectRequestCount = 0
    private var quickConnectRequests: [Int: CheckedContinuation<QuickConnectState, Error>] = [:]
    private var quickConnectWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    private var quickConnectPollCount = 0
    private var quickConnectPolls: [Int: CheckedContinuation<UserSession?, Error>] = [:]
    private var quickConnectPollWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func suspendConnectionRequest() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let requestID = connectionRequestCount
            connectionRequestCount += 1
            connectionRequests[requestID] = continuation
            resumeConnectionWaiters()
        }
    }

    func waitForConnectionRequestCount(_ expectedCount: Int) async {
        guard connectionRequestCount < expectedCount else { return }

        await withCheckedContinuation { continuation in
            connectionWaiters.append((expectedCount, continuation))
        }
    }

    func failConnectionRequest(_ requestID: Int, error: Error) {
        connectionRequests.removeValue(forKey: requestID)?.resume(throwing: error)
    }

    func resolveConnectionRequest(_ requestID: Int) {
        connectionRequests.removeValue(forKey: requestID)?.resume()
    }

    func suspendQuickConnectRequest() async throws -> QuickConnectState {
        try await withCheckedThrowingContinuation { continuation in
            let requestID = quickConnectRequestCount
            quickConnectRequestCount += 1
            quickConnectRequests[requestID] = continuation
            resumeQuickConnectWaiters()
        }
    }

    func waitForQuickConnectRequestCount(_ expectedCount: Int) async {
        guard quickConnectRequestCount < expectedCount else { return }

        await withCheckedContinuation { continuation in
            quickConnectWaiters.append((expectedCount, continuation))
        }
    }

    func resolveQuickConnectRequest(_ requestID: Int, state: QuickConnectState) {
        quickConnectRequests.removeValue(forKey: requestID)?.resume(returning: state)
    }

    func suspendQuickConnectPoll() async throws -> UserSession? {
        try await withCheckedThrowingContinuation { continuation in
            let requestID = quickConnectPollCount
            quickConnectPollCount += 1
            quickConnectPolls[requestID] = continuation
            resumeQuickConnectPollWaiters()
        }
    }

    func waitForQuickConnectPollCount(_ expectedCount: Int) async {
        guard quickConnectPollCount < expectedCount else { return }

        await withCheckedContinuation { continuation in
            quickConnectPollWaiters.append((expectedCount, continuation))
        }
    }

    func resolveQuickConnectPoll(_ requestID: Int, session: UserSession?) {
        quickConnectPolls.removeValue(forKey: requestID)?.resume(returning: session)
    }

    private func resumeConnectionWaiters() {
        let ready = connectionWaiters.filter { connectionRequestCount >= $0.count }
        connectionWaiters.removeAll { connectionRequestCount >= $0.count }
        ready.forEach { $0.continuation.resume() }
    }

    private func resumeQuickConnectWaiters() {
        let ready = quickConnectWaiters.filter { quickConnectRequestCount >= $0.count }
        quickConnectWaiters.removeAll { quickConnectRequestCount >= $0.count }
        ready.forEach { $0.continuation.resume() }
    }

    private func resumeQuickConnectPollWaiters() {
        let ready = quickConnectPollWaiters.filter { quickConnectPollCount >= $0.count }
        quickConnectPollWaiters.removeAll { quickConnectPollCount >= $0.count }
        ready.forEach { $0.continuation.resume() }
    }
}
