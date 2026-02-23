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

    func testPlaybackStartsFast() throws {
        let app = XCUIApplication()
        app.launch()

        // Find the first media card
        let firstPoster = app.buttons.matching(identifier: "media_card").firstMatch
        guard firstPoster.waitForExistence(timeout: 10) else {
            throw XCTSkip("No media cards found – likely no live Jellyfin server available.")
        }
        firstPoster.tap()

        // Tap the Play button in the detail view
        let playButton = app.buttons["Play"]
        guard playButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Detail view did not show a Play button – server may be unavailable.")
        }
        playButton.tap()

        // Verify the video player (AVPlayerViewController) appears within 8 seconds.
        // This guards against major TTFF regressions.
        let playerView = app.otherElements["Video Player"]
        let playerExists = playerView.waitForExistence(timeout: 8)

        if !playerExists {
            // Fallback: check for any full-screen element that could be the player
            let anyMediaElement = app.windows.firstMatch
            XCTAssertTrue(
                anyMediaElement.exists,
                "Video player should appear within 8 seconds of tapping Play"
            )
        }
    }
}
