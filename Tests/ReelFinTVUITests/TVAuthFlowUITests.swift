import XCTest

final class TVAuthFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = [
            "-reelfin-mock-mode", "-reelfin-ui-logged-out",
            "-reelfin-tv-auth-screen", "onboarding",
            "-reelfin-tv-onboarding-page", "0"
        ]
        app.launch()
    }

    func testFirstPageHasStableScreenIdentityAndPrimaryFocus() {
        XCTAssertTrue(app.otherElements["tv_onboarding_screen"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["tv_onboarding_primary_cta"].hasFocus)
        XCTAssertFalse(app.buttons["tv_onboarding_back"].exists)
    }

    func testSelectAdvancesAndMenuRetreatsWithoutExiting() {
        XCTAssertTrue(app.buttons["tv_onboarding_primary_cta"].waitForExistence(timeout: 8))

        XCUIRemote.shared.press(.select)

        XCTAssertTrue(app.staticTexts["tv_onboarding_title"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["tv_onboarding_back"].exists)

        XCUIRemote.shared.press(.menu)

        XCTAssertFalse(app.buttons["tv_onboarding_back"].exists)
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testActionsStayInsideSafeRectangle() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 8))

        let screen = app.otherElements["tv_onboarding_screen"]
        XCTAssertTrue(screen.waitForExistence(timeout: 3))
        XCTAssertTrue(screen.frame.contains(window.frame))

        let safeRectangle = window.frame.insetBy(dx: 80, dy: 60)

        let primaryButton = app.buttons["tv_onboarding_primary_cta"]
        XCTAssertTrue(primaryButton.waitForExistence(timeout: 3))
        XCTAssertTrue(
            safeRectangle.contains(primaryButton.frame),
            "Primary frame \(primaryButton.frame) must be inside \(safeRectangle)."
        )

        XCUIRemote.shared.press(.select)

        let backButton = app.buttons["tv_onboarding_back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 3))
        XCTAssertTrue(
            safeRectangle.contains(backButton.frame),
            "Back frame \(backButton.frame) must be inside \(safeRectangle)."
        )
        XCTAssertTrue(
            safeRectangle.contains(primaryButton.frame),
            "Primary frame \(primaryButton.frame) must be inside \(safeRectangle)."
        )
    }

    func testFinalPrimaryActionHasSingleLineAllocation() {
        let pageTitles = [
            "Browse without friction",
            "Spot Direct Play",
            "Connect your way"
        ]

        for title in pageTitles {
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 3))
        }

        let primaryButton = app.buttons["tv_onboarding_primary_cta"]
        XCTAssertEqual(primaryButton.label, "Connect My Server")
        XCTAssertGreaterThanOrEqual(
            primaryButton.frame.width,
            480,
            "The final CTA needs enough horizontal space to keep its 30 pt label on one line."
        )
    }
}
