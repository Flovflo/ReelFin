import XCTest

final class TVLiveNavigationSmokeUITests: XCTestCase {
    private struct LiveCredentials {
        let serverURL: String
        let username: String
        let password: String
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testExistingSessionHomeStartsFocusedOnHeroPlay() throws {
        let app = launchLiveApp()

        try ensureAuthenticated(in: app)

        let heroPlayButton = app.buttons["home_featured_play_button"].firstMatch
        XCTAssertTrue(heroPlayButton.waitForExistence(timeout: 12))
        XCTAssertTrue(waitUntilAccessibilityValue(heroPlayButton, expectedValue: "focused", timeout: 8))
        XCTAssertTrue(accessibilityValueStays(heroPlayButton, expectedValue: "focused", duration: 0.8))
    }

    func testExistingSessionVerticalNavigationStaysStable() throws {
        let app = launchLiveApp()

        try ensureAuthenticated(in: app)

        let heroPlayButton = app.buttons["home_featured_play_button"].firstMatch
        let homeNavigationButton = app.descendants(matching: .any)["tv_top_navigation_watchNow"].firstMatch

        XCTAssertTrue(heroPlayButton.waitForExistence(timeout: 12))
        XCTAssertTrue(waitUntilAccessibilityValue(heroPlayButton, expectedValue: "focused", timeout: 8))

        XCUIRemote.shared.press(.down)
        let firstRowCard = try XCTUnwrap(waitForFocusedMediaCard(in: app, timeout: 8))
        XCTAssertTrue(accessibilityValueStays(firstRowCard, expectedValue: "focused", duration: 0.8))
        let firstRowIdentifier = firstRowCard.identifier

        XCUIRemote.shared.press(.down)
        let secondRowCard = try XCTUnwrap(
            waitForFocusedMediaCard(
                in: app,
                excludingIdentifier: firstRowIdentifier,
                timeout: 8
            )
        )
        XCTAssertNotEqual(secondRowCard.identifier, firstRowIdentifier)
        XCTAssertTrue(accessibilityValueStays(secondRowCard, expectedValue: "focused", duration: 0.8))

        XCUIRemote.shared.press(.up)
        XCTAssertTrue(waitUntilAccessibilityValue(firstRowCard, expectedValue: "focused", timeout: 8))
        XCTAssertTrue(accessibilityValueStays(firstRowCard, expectedValue: "focused", duration: 0.8))

        XCUIRemote.shared.press(.up)
        XCTAssertTrue(waitUntilAccessibilityValue(heroPlayButton, expectedValue: "focused", timeout: 8))
        XCTAssertTrue(accessibilityValueStays(heroPlayButton, expectedValue: "focused", duration: 0.8))

        XCUIRemote.shared.press(.up)
        XCTAssertTrue(homeNavigationButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilAccessibilityValue(homeNavigationButton, expectedValue: "focused", timeout: 8))
        XCTAssertTrue(accessibilityValueStays(homeNavigationButton, expectedValue: "focused", duration: 0.6))

        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitUntilAccessibilityValue(heroPlayButton, expectedValue: "focused", timeout: 8))
        XCTAssertTrue(accessibilityValueStays(heroPlayButton, expectedValue: "focused", duration: 0.8))
    }

    func testExistingSessionDetailAndBackRestoreFocusedCard() throws {
        let app = launchLiveApp()

        try ensureAuthenticated(in: app)

        let heroPlayButton = app.buttons["home_featured_play_button"].firstMatch
        XCTAssertTrue(heroPlayButton.waitForExistence(timeout: 12))
        XCTAssertTrue(waitUntilAccessibilityValue(heroPlayButton, expectedValue: "focused", timeout: 8))

        XCUIRemote.shared.press(.down)
        let rowCard = try XCTUnwrap(waitForFocusedMediaCard(in: app, timeout: 8))
        XCTAssertTrue(accessibilityValueStays(rowCard, expectedValue: "focused", duration: 0.8))

        XCUIRemote.shared.press(.select)

        let detailPlayButton = app.buttons["detail_play_button"].firstMatch
        XCTAssertTrue(detailPlayButton.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntilAccessibilityValue(detailPlayButton, expectedValue: "focused", timeout: 8))

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitUntilAccessibilityValue(rowCard, expectedValue: "focused", timeout: 8))
        XCTAssertTrue(accessibilityValueStays(rowCard, expectedValue: "focused", duration: 0.8))
    }

    private func launchLiveApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
        return app
    }

    private func ensureAuthenticated(in app: XCUIApplication) throws {
        if waitForHome(in: app) {
            return
        }

        let credentials = loadLiveCredentials()
        advanceThroughOnboardingIfNeeded(app)

        let serverField = app.textFields["login_server_field"].firstMatch
        XCTAssertTrue(serverField.waitForExistence(timeout: 10))
        replaceText(in: serverField, with: credentials.serverURL)

        let continueButton = app.buttons["login_server_continue"].firstMatch
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        continueButton.tap()

        let usernameField = app.textFields["login_username_field"].firstMatch
        XCTAssertTrue(usernameField.waitForExistence(timeout: 12))
        replaceText(in: usernameField, with: credentials.username)

        let passwordField = app.secureTextFields["login_password_field"].firstMatch
        XCTAssertTrue(passwordField.waitForExistence(timeout: 8))
        replaceText(in: passwordField, with: credentials.password)

        let signInButton = app.buttons["login_sign_in"].firstMatch
        XCTAssertTrue(signInButton.waitForExistence(timeout: 5))
        signInButton.tap()

        XCTAssertTrue(waitForHome(in: app))
    }

    private func waitForHome(in app: XCUIApplication) -> Bool {
        let heroPlayButton = app.buttons["home_featured_play_button"].firstMatch
        if heroPlayButton.waitForExistence(timeout: 8) {
            return true
        }

        return app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "media_card_button_")
        ).firstMatch.waitForExistence(timeout: 8)
    }

    private func advanceThroughOnboardingIfNeeded(_ app: XCUIApplication) {
        let serverField = app.textFields["login_server_field"].firstMatch
        if serverField.exists {
            return
        }

        let onboardingButton = app.buttons["tv_onboarding_primary_cta"].firstMatch
        guard onboardingButton.waitForExistence(timeout: 2) else { return }

        for _ in 0..<6 {
            XCUIRemote.shared.press(.select)

            if serverField.waitForExistence(timeout: 1.5) || app.otherElements["tv_login_view"].firstMatch.exists {
                return
            }
        }
    }

    private func loadLiveCredentials() -> LiveCredentials {
        let environment = ProcessInfo.processInfo.environment

        if
            let serverURL = environment["REELFIN_TEST_SERVER_URL"],
            let username = environment["REELFIN_TEST_USERNAME"],
            let password = environment["REELFIN_TEST_PASSWORD"],
            !serverURL.isEmpty,
            !username.isEmpty,
            !password.isEmpty
        {
            return LiveCredentials(
                serverURL: serverURL,
                username: username,
                password: password
            )
        }

        return LiveCredentials(
            serverURL: "https://demo.reelfin.app",
            username: "preview",
            password: "password"
        )
    }

    private func replaceText(in field: XCUIElement, with value: String) {
        field.tap()

        if let currentValue = field.value as? String,
           !currentValue.isEmpty,
           currentValue != value
        {
            let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
            field.typeText(deletes)
        }

        field.typeText(value)
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
