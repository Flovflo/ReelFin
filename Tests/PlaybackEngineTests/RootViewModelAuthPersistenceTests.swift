import Shared
@testable import ReelFinUI
import XCTest

@MainActor
final class RootViewModelAuthPersistenceTests: XCTestCase {
    func testRecreatedRootLifecycleOnSameClientReceivesInvalidation() async {
        let invalidations = TestSessionInvalidationSource()
        let api = MockJellyfinAPIClient(
            authenticated: true,
            sessionInvalidationsOverride: { invalidations.subscribe() }
        )
        let dependencies = ReelFinPreviewFactory.dependencies(authenticated: true, apiClient: api)
        let firstViewModel = RootViewModel(dependencies: dependencies)
        let firstLifecycle = Task { await firstViewModel.runRootLifecycle() }

        let firstDidBootstrap = await waitUntil { firstViewModel.didBootstrap }
        XCTAssertTrue(firstDidBootstrap)
        firstLifecycle.cancel()
        await firstLifecycle.value

        let replacementViewModel = RootViewModel(dependencies: dependencies)
        let replacementLifecycle = Task { await replacementViewModel.runRootLifecycle() }
        defer { replacementLifecycle.cancel() }

        let replacementDidBootstrap = await waitUntil { replacementViewModel.didBootstrap }
        XCTAssertTrue(replacementDidBootstrap)
        await api.signOut()
        invalidations.yield(.unauthorized)

        let didLeaveAuthenticatedShell = await waitUntil { !replacementViewModel.isAuthenticated }
        XCTAssertTrue(didLeaveAuthenticatedShell)
        XCTAssertTrue(replacementViewModel.didBootstrap)
        XCTAssertTrue(firstViewModel.isAuthenticated)
    }

    func testRootLifecycleCancellationDuringSessionRecheckPreservesAuthenticatedState() async {
        let (events, continuation) = AsyncStream<SessionInvalidationEvent>.makeStream()
        let lookup = SuspendedSessionLookup(
            initialSession: UserSession(userID: "user-1", username: "Flo", token: "token-1")
        )
        let api = MockJellyfinAPIClient(
            authenticated: true,
            sessionInvalidations: events,
            currentSessionOverride: { await lookup.currentSession() }
        )
        let dependencies = ReelFinPreviewFactory.dependencies(authenticated: true, apiClient: api)
        let viewModel = RootViewModel(dependencies: dependencies)
        let lifecycle = Task { await viewModel.runRootLifecycle() }

        let didBootstrap = await waitUntil { viewModel.didBootstrap }
        XCTAssertTrue(didBootstrap)
        continuation.yield(.unauthorized)
        let didSuspend = await waitUntilAsync { await lookup.isBlocked }
        XCTAssertTrue(didSuspend)

        lifecycle.cancel()
        await lookup.resume(returning: nil)
        continuation.finish()
        await lifecycle.value

        XCTAssertTrue(viewModel.isAuthenticated)
        XCTAssertTrue(viewModel.didBootstrap)
    }

    func testCompleteLoginDuringSessionRecheckPreservesReplacementAuthentication() async {
        let (events, continuation) = AsyncStream<SessionInvalidationEvent>.makeStream()
        let lookup = SuspendedSessionLookup(
            initialSession: UserSession(userID: "user-1", username: "Flo", token: "token-1")
        )
        let api = MockJellyfinAPIClient(
            authenticated: true,
            sessionInvalidations: events,
            currentSessionOverride: { await lookup.currentSession() }
        )
        let dependencies = ReelFinPreviewFactory.dependencies(authenticated: true, apiClient: api)
        let viewModel = RootViewModel(dependencies: dependencies)
        let lifecycle = Task { await viewModel.runRootLifecycle() }
        defer { lifecycle.cancel() }

        let didBootstrap = await waitUntil { viewModel.didBootstrap }
        XCTAssertTrue(didBootstrap)
        continuation.yield(.unauthorized)
        let didSuspend = await waitUntilAsync { await lookup.isBlocked }
        XCTAssertTrue(didSuspend)

        let replacement = UserSession(userID: "user-2", username: "Flo 2", token: "token-2")
        viewModel.completeLogin(replacement)
        await lookup.resume(returning: nil)
        continuation.finish()
        await lifecycle.value

        XCTAssertTrue(viewModel.isAuthenticated)
        XCTAssertTrue(viewModel.didBootstrap)
        XCTAssertEqual(dependencies.settingsStore.lastSession, replacement)
    }

    func testRootLifecycleLeavesAuthenticatedShellAfterSessionInvalidation() async {
        let (events, continuation) = AsyncStream<SessionInvalidationEvent>.makeStream()
        let api = MockJellyfinAPIClient(authenticated: true, sessionInvalidations: events)
        let dependencies = ReelFinPreviewFactory.dependencies(authenticated: true, apiClient: api)
        let viewModel = RootViewModel(dependencies: dependencies)
        let lifecycle = Task { await viewModel.runRootLifecycle() }
        defer { lifecycle.cancel() }

        let didBootstrap = await waitUntil { viewModel.didBootstrap }
        XCTAssertTrue(didBootstrap)
        await api.signOut()
        continuation.yield(.unauthorized)
        continuation.finish()
        await lifecycle.value

        XCTAssertTrue(viewModel.didBootstrap)
        XCTAssertFalse(viewModel.isAuthenticated)
    }

    func testRootLifecycleIgnoresInvalidationWhenReplacementSessionExists() async {
        let (events, continuation) = AsyncStream<SessionInvalidationEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let api = MockJellyfinAPIClient(authenticated: true, sessionInvalidations: events)
        continuation.yield(.unauthorized)
        continuation.finish()
        let dependencies = ReelFinPreviewFactory.dependencies(authenticated: true, apiClient: api)
        let viewModel = RootViewModel(dependencies: dependencies)
        await viewModel.runRootLifecycle()

        XCTAssertTrue(viewModel.didBootstrap)
        XCTAssertTrue(viewModel.isAuthenticated)
    }

    func testBootstrapDoesNotAuthenticateFromPersistedIdentityAlone() async {
        let dependencies = ReelFinPreviewFactory.dependencies(authenticated: false)
        let savedSession = UserSession(userID: "user-1", username: "Flo", token: "token-1")
        dependencies.settingsStore.lastSession = savedSession

        let viewModel = RootViewModel(dependencies: dependencies)
        await viewModel.bootstrap()

        XCTAssertFalse(viewModel.isAuthenticated)
        XCTAssertTrue(viewModel.didBootstrap)
        XCTAssertFalse(dependencies.settingsStore.hasCompletedOnboarding)
    }

    func testBootstrapRestoresAuthenticatedSessionAndBackfillsOnboardingVersion() async {
        let dependencies = ReelFinPreviewFactory.dependencies(authenticated: true)

        let viewModel = RootViewModel(dependencies: dependencies)
        await viewModel.bootstrap()

        XCTAssertTrue(viewModel.isAuthenticated)
        XCTAssertTrue(viewModel.didBootstrap)
        XCTAssertTrue(dependencies.settingsStore.hasCompletedOnboarding)
        XCTAssertEqual(
            dependencies.settingsStore.completedOnboardingVersion,
            ReelFinOnboardingVersion.current
        )
    }

    func testCompleteLoginMarksOnboardingAsCompleted() {
        let dependencies = ReelFinPreviewFactory.dependencies(authenticated: false)
        let session = UserSession(userID: "user-2", username: "Flo", token: "token-2")

        let viewModel = RootViewModel(dependencies: dependencies)
        viewModel.completeLogin(session)

        XCTAssertTrue(viewModel.isAuthenticated)
        XCTAssertTrue(viewModel.didBootstrap)
        XCTAssertEqual(dependencies.settingsStore.lastSession?.userID, "user-2")
        XCTAssertTrue(dependencies.settingsStore.hasCompletedOnboarding)
        XCTAssertEqual(
            dependencies.settingsStore.completedOnboardingVersion,
            ReelFinOnboardingVersion.current
        )
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))

        while clock.now < deadline {
            if condition() {
                return true
            }
            await Task.yield()
        }

        return condition()
    }

    private func waitUntilAsync(_ condition: () async -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))

        while clock.now < deadline {
            if await condition() {
                return true
            }
            await Task.yield()
        }

        return await condition()
    }
}

private actor SuspendedSessionLookup {
    private let initialSession: UserSession
    private var didReturnInitialSession = false
    private(set) var isBlocked = false
    private var continuation: CheckedContinuation<UserSession?, Never>?

    init(initialSession: UserSession) {
        self.initialSession = initialSession
    }

    func currentSession() async -> UserSession? {
        guard didReturnInitialSession else {
            didReturnInitialSession = true
            return initialSession
        }

        isBlocked = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(returning session: UserSession?) {
        isBlocked = false
        continuation?.resume(returning: session)
        continuation = nil
    }
}

private final class TestSessionInvalidationSource: @unchecked Sendable {
    private typealias Continuation = AsyncStream<SessionInvalidationEvent>.Continuation

    private let lock = NSLock()
    private var continuations: [UUID: Continuation] = [:]

    func subscribe() -> AsyncStream<SessionInvalidationEvent> {
        let identifier = UUID()
        let subscription = AsyncStream<SessionInvalidationEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        subscription.continuation.onTermination = { [weak self] _ in
            self?.removeContinuation(for: identifier)
        }

        lock.lock()
        continuations[identifier] = subscription.continuation
        lock.unlock()
        return subscription.stream
    }

    func yield(_ event: SessionInvalidationEvent) {
        lock.lock()
        let subscribers = Array(continuations.values)
        lock.unlock()

        for continuation in subscribers {
            continuation.yield(event)
        }
    }

    private func removeContinuation(for identifier: UUID) {
        lock.lock()
        continuations[identifier] = nil
        lock.unlock()
    }
}
