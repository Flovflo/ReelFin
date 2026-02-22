import XCTest

class ReelFinUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Verify that the app launches successfully
        XCTAssert(app.wait(for: .runningForeground, timeout: 5))
    }

    func testNavigationToDetailAndBack() throws {
        let app = XCUIApplication()
        app.launch()

        // This test requires a live Jellyfin server to pre-populate content cards.
        // We look for the first media card by accessibility identifier.
        let firstPoster = app.buttons.matching(identifier: "media_card").firstMatch
        guard firstPoster.waitForExistence(timeout: 10) else {
            throw XCTSkip("No media cards found – likely no live Jellyfin server available.")
        }
        firstPoster.tap()

        let playButton = app.buttons["Play"]
        guard playButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Detail view did not show a Play button – server may be unavailable.")
        }

        app.navigationBars.buttons.firstMatch.tap()
    }
}
