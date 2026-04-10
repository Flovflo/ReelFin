import Shared
@testable import ReelFinUI
import XCTest

@MainActor
final class RootViewModelAuthPersistenceTests: XCTestCase {
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
        XCTAssertEqual(dependencies.settingsStore.lastSession?.userID, "user-2")
        XCTAssertTrue(dependencies.settingsStore.hasCompletedOnboarding)
        XCTAssertEqual(
            dependencies.settingsStore.completedOnboardingVersion,
            ReelFinOnboardingVersion.current
        )
    }
}
