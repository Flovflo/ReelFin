import XCTest

final class TVAuthFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEveryOnboardingPageLaunchesWithStableIdentityAndPrimaryFocus() {
        let expectedTitles = [
            "Your Jellyfin on Apple TV",
            "Find what to watch",
            "Know the playback path",
            "Connect in seconds"
        ]

        for (page, expectedTitle) in expectedTitles.enumerated() {
            let app = launchOnboarding(page: page)

            XCTAssertTrue(app.otherElements["tv_onboarding_screen"].waitForExistence(timeout: 8))
            let titleAndExplanation = app.descendants(matching: .any)["tv_onboarding_title"]
            XCTAssertTrue(titleAndExplanation.waitForExistence(timeout: 3))
            XCTAssertTrue(titleAndExplanation.label.hasPrefix(expectedTitle))
            XCTAssertTrue(waitForFocus(app.buttons["tv_onboarding_primary_cta"]))
            XCTAssertEqual(app.buttons["tv_onboarding_back"].exists, page > 0)
        }
    }

    func testMenuOnFirstPageIsConsumedWithoutExiting() {
        let app = launchOnboarding(page: 0)
        let primaryButton = app.buttons["tv_onboarding_primary_cta"]
        XCTAssertTrue(primaryButton.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForFocus(primaryButton))

        XCUIRemote.shared.press(.menu)

        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertFalse(app.buttons["tv_onboarding_back"].exists)
        XCTAssertTrue(waitForFocus(primaryButton))
    }

    func testSelectAdvancesAndMenuRetreatsWithPrimaryFocusRestored() {
        let app = launchOnboarding(page: 0)
        let primaryButton = app.buttons["tv_onboarding_primary_cta"]
        XCTAssertTrue(primaryButton.waitForExistence(timeout: 8))

        XCUIRemote.shared.press(.select)

        XCTAssertTrue(app.buttons["tv_onboarding_back"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForFocus(primaryButton))

        XCUIRemote.shared.press(.menu)

        XCTAssertTrue(waitForDisappearance(app.buttons["tv_onboarding_back"]))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(waitForFocus(primaryButton))
    }

    func testActionsStayInsideSafeRectangleOnEveryPage() {
        for page in 0..<4 {
            let app = launchOnboarding(page: page)
            let window = app.windows.firstMatch
            XCTAssertTrue(window.waitForExistence(timeout: 8))

            let safeRectangle = window.frame.insetBy(dx: 80, dy: 60)
            let primaryButton = app.buttons["tv_onboarding_primary_cta"]
            XCTAssertTrue(primaryButton.waitForExistence(timeout: 3))
            XCTAssertTrue(
                safeRectangle.contains(primaryButton.frame),
                "Page \(page) primary frame \(primaryButton.frame) must be inside \(safeRectangle)."
            )

            let backButton = app.buttons["tv_onboarding_back"]
            if page == 0 {
                XCTAssertFalse(backButton.exists)
            } else {
                XCTAssertTrue(backButton.waitForExistence(timeout: 3))
                XCTAssertTrue(
                    safeRectangle.contains(backButton.frame),
                    "Page \(page) Back frame \(backButton.frame) must be inside \(safeRectangle)."
                )
            }
        }
    }

    func testFinalPrimaryActionHasSingleLineAllocation() {
        let app = launchOnboarding(page: 3)
        let primaryButton = app.buttons["tv_onboarding_primary_cta"]

        XCTAssertTrue(primaryButton.waitForExistence(timeout: 8))
        XCTAssertEqual(primaryButton.label, "Connect My Server")
        XCTAssertGreaterThanOrEqual(
            primaryButton.frame.width,
            480,
            "The final CTA needs enough horizontal space to keep its 30 pt label on one line."
        )
    }

    private func launchOnboarding(page: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-reelfin-mock-mode", "-reelfin-ui-logged-out",
            "-reelfin-tv-auth-screen", "onboarding",
            "-reelfin-tv-onboarding-page", String(page)
        ]
        app.launch()
        return app
    }

    private func waitForFocus(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "hasFocus == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
