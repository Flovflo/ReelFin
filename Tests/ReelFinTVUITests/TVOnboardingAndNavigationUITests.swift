import XCTest

final class TVOnboardingAndNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingAdvancesToLogin() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-reelfin-mock-mode",
            "-reelfin-ui-logged-out",
            "-reelfin-force-onboarding",
            "-reelfin-tv-auth-screen", "onboarding"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        let primaryCTA = app.descendants(matching: .any)["tv_onboarding_primary_cta"].firstMatch
        XCTAssertTrue(primaryCTA.waitForExistence(timeout: 10))

        for _ in 0..<TVOnboardingScreenCount.total {
            XCUIRemote.shared.press(.select)
        }

        let loginView = app.descendants(matching: .any)["tv_login_view"].firstMatch
        XCTAssertTrue(loginView.waitForExistence(timeout: 8))
    }

    func testHomeVerticalNavigationStaysStableAcrossHeroRowsAndTopNavigation() throws {
        throw XCTSkip("Superseded by TVLiveNavigationSmokeUITests on the connected simulator.")
    }

    func testHeroPlayButtonOpensPlayerAfterReturningFromRow() throws {
        throw XCTSkip("Superseded by TVLiveNavigationSmokeUITests on the connected simulator.")
    }

    func testMovingDownFromHeroOpensDetailWithPlayFocused() throws {
        throw XCTSkip("Superseded by TVLiveNavigationSmokeUITests on the connected simulator.")
    }

    private func launchMockAuthenticatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-reelfin-mock-mode"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        return app
    }

    private func playerScreen(in app: XCUIApplication) -> XCUIElement {
        app.otherElements["native_player_screen"].firstMatch
    }

    private func waitUntilAccessibilityValue(
        _ element: XCUIElement,
        expectedValue: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if element.exists, let value = element.value as? String, value == expectedValue {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return element.exists && (element.value as? String) == expectedValue
    }

    private func accessibilityValueStays(
        _ element: XCUIElement,
        expectedValue: String,
        duration: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(duration)

        while Date() < deadline {
            guard element.exists else { return false }
            guard (element.value as? String) == expectedValue else { return false }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return element.exists && (element.value as? String) == expectedValue
    }

    private func waitForFocusedMediaCard(
        in app: XCUIApplication,
        excludingIdentifier: String? = nil,
        timeout: TimeInterval
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let focusedCard = focusedMediaCard(in: app, excludingIdentifier: excludingIdentifier) {
                return focusedCard
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return focusedMediaCard(in: app, excludingIdentifier: excludingIdentifier)
    }

    private func focusedMediaCard(
        in app: XCUIApplication,
        excludingIdentifier: String? = nil
    ) -> XCUIElement? {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "media_card_button_")
        )
        .allElementsBoundByIndex
        .first { element in
            guard element.exists else { return false }
            guard (element.value as? String) == "focused" else { return false }
            if let excludingIdentifier {
                return element.identifier != excludingIdentifier
            }
            return true
        }
    }
}

private enum TVOnboardingScreenCount {
    static let total = 5
}
