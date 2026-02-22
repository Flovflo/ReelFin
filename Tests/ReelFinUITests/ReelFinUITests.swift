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
        
        let firstPoster = app.buttons.firstMatch
        XCTAssertTrue(firstPoster.waitForExistence(timeout: 10))
        firstPoster.tap()
        
        let playButton = app.buttons["Play"]
        XCTAssertTrue(playButton.waitForExistence(timeout: 5))
        
        app.navigationBars.buttons.firstMatch.tap()
    }
}
