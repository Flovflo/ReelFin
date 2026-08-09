import Shared
@testable import ReelFinUI
import XCTest

@MainActor
final class RootViewModelAuthPersistenceTests: XCTestCase {
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
}
