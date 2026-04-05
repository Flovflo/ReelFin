import XCTest

final class PlaybackLiveSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLiveLoginAndStartPlayback() throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            let serverURL = environment["REELFIN_TEST_SERVER_URL"],
            let username = environment["REELFIN_TEST_USERNAME"],
            let password = environment["REELFIN_TEST_PASSWORD"],
            !serverURL.isEmpty,
            !username.isEmpty,
            !password.isEmpty
        else {
            throw XCTSkip("Set REELFIN_TEST_SERVER_URL / REELFIN_TEST_USERNAME / REELFIN_TEST_PASSWORD to run the live UI smoke test.")
        }

        let app = XCUIApplication()
        app.launchArguments += [
            "-reelfin-force-onboarding",
            "-reelfin-ui-reset-auth-state"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        advanceThroughOnboardingIfNeeded(app)

        let serverField = app.textFields["login_server_field"].firstMatch
        XCTAssertTrue(serverField.waitForExistence(timeout: 10))
        replaceText(in: serverField, with: serverURL)

        let continueButton = app.buttons["login_server_continue"].firstMatch
        XCTAssertTrue(continueButton.exists)
        continueButton.tap()

        let usernameField = app.textFields["login_username_field"].firstMatch
        XCTAssertTrue(usernameField.waitForExistence(timeout: 12))
        replaceText(in: usernameField, with: username)

        let passwordField = app.secureTextFields["login_password_field"].firstMatch
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5))
        replaceText(in: passwordField, with: password)

        let signInButton = app.buttons["login_sign_in"].firstMatch
        XCTAssertTrue(signInButton.exists)
        signInButton.tap()

        let homeTab = app.tabBars.buttons["Home"].firstMatch
        XCTAssertTrue(homeTab.waitForExistence(timeout: 20))

        let firstPoster = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "media_card_button_")
        ).firstMatch
        XCTAssertTrue(firstPoster.waitForExistence(timeout: 20))
        firstPoster.tap()

        let playButton = app.buttons["Play"].firstMatch
        XCTAssertTrue(playButton.waitForExistence(timeout: 12))
        playButton.tap()

        let playerScreen = app.otherElements["native_player_screen"].firstMatch
        XCTAssertTrue(playerScreen.waitForExistence(timeout: 15))
    }

    private func advanceThroughOnboardingIfNeeded(_ app: XCUIApplication) {
        let serverField = app.textFields["login_server_field"].firstMatch
        if serverField.exists {
            return
        }

        for _ in 0 ..< 4 {
            let onboardingButton = app.buttons["onboarding_primary_cta"].firstMatch
            XCTAssertTrue(onboardingButton.waitForExistence(timeout: 5))
            onboardingButton.tap()

            if serverField.waitForExistence(timeout: 1.5) {
                return
            }
        }

        XCTFail("Expected onboarding to advance to server entry.")
    }

    private func replaceText(in field: XCUIElement, with value: String) {
        field.tap()

        if let currentValue = field.value as? String,
           !currentValue.isEmpty,
           currentValue != value,
           currentValue != "https://server.example.com" {
            let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
            field.typeText(deletes)
        }

        field.typeText(value)
    }
}
