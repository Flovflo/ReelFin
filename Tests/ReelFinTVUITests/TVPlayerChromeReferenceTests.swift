import XCTest

final class TVPlayerChromeReferenceTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDownFromHiddenChromeOpensSettingsWithInfoFocused() {
        let app = XCUIApplication()
        app.launchArguments = ["-reelfin-tv-player-chrome-reference"]
        app.launch()

        let root = app.otherElements["native_player_tv_chrome_reference"]
        XCTAssertTrue(root.waitForExistence(timeout: 8))
        assertReferenceState("chrome=hidden;panel=none;inputFocused=true", in: app)

        XCUIRemote.shared.press(.down)

        let settingsPanel = app.otherElements["native_player_settings_panel"]
        let infoButton = app.buttons["native_player_info_button"]
        XCTAssertTrue(settingsPanel.waitForExistence(timeout: 5))
        XCTAssertTrue(infoButton.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForFocus(infoButton), "Down must open Settings and focus Info in one press.")
        assertReferenceState("chrome=visible;panel=settings;inputFocused=false", in: app)

        XCUIRemote.shared.press(.select)

        XCTAssertTrue(app.otherElements["native_player_info_panel"].waitForExistence(timeout: 5))
        assertReferenceState("chrome=visible;panel=info;inputFocused=false", in: app)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "tv-player-hidden-down-info-route"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertReferenceState(_ expected: String, in app: XCUIApplication) {
        let marker = app.otherElements["native_player_tv_chrome_reference_state"]
        XCTAssertTrue(marker.waitForExistence(timeout: 3))
        let predicate = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: marker)
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            "Expected reference state \(expected), got \(String(describing: marker.value))."
        )
    }

    private func waitForFocus(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "hasFocus == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
