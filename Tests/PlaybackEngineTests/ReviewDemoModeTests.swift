import Shared
@testable import ReelFinUI
import XCTest

@MainActor
final class ReviewDemoModeTests: XCTestCase {
    func testReviewCredentialsBypassJellyfinNetworking() async {
        let apiClient = MockJellyfinAPIClient(authenticated: false)
        let dependencies = ReelFinPreviewFactory.dependencies(
            authenticated: false,
            apiClient: apiClient
        )
        let viewModel = LoginViewModel(dependencies: dependencies)
        viewModel.serverURLText = "https://review.reelfin.app"
        viewModel.username = "review"
        viewModel.password = "ReelFin-Review-2026"

        let connectionSucceeded = await viewModel.testConnection()
        let session = await viewModel.login()

        XCTAssertTrue(connectionSucceeded)
        XCTAssertEqual(session?.userID, "review-demo-user")
        XCTAssertEqual(apiClient.testConnectionCallCount, 0)
        XCTAssertEqual(apiClient.configureCallCount, 0)
        XCTAssertEqual(apiClient.authenticateCallCount, 0)
    }

    func testRegularCredentialsStillUseJellyfinClient() async {
        let apiClient = MockJellyfinAPIClient(authenticated: false)
        let dependencies = ReelFinPreviewFactory.dependencies(
            authenticated: false,
            apiClient: apiClient
        )
        let viewModel = LoginViewModel(dependencies: dependencies)
        viewModel.serverURLText = "https://server.example"
        viewModel.username = "regular"
        viewModel.password = "password"

        _ = await viewModel.testConnection()
        _ = await viewModel.login()

        XCTAssertEqual(apiClient.testConnectionCallCount, 1)
        XCTAssertEqual(apiClient.configureCallCount, 1)
        XCTAssertEqual(apiClient.authenticateCallCount, 1)
    }
}
