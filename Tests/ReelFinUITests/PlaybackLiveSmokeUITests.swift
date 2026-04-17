import XCTest

final class PlaybackLiveSmokeUITests: XCTestCase {
    private struct LiveCredentials {
        let serverURL: String
        let username: String
        let password: String
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testExistingSessionMoviePlaybackSmoke() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        try ensureAuthenticated(in: app)
        try runPlaybackScenario(
            in: app,
            scenario: "movie",
            preferredKinds: ["recentlyAddedMovies", "movies", "popular", "trending"]
        )
    }

    func testExistingSessionSeriesPlaybackSmoke() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        try ensureAuthenticated(in: app)
        try runPlaybackScenario(
            in: app,
            scenario: "series",
            preferredKinds: ["recentlyAddedSeries", "shows", "nextUp", "continueWatching"]
        )
    }

    func testLiveLoginAndStartPlayback() throws {
        let credentials = try requireLiveCredentials()
        let app = XCUIApplication()
        app.launchArguments += [
            "-reelfin-force-onboarding",
            "-reelfin-ui-reset-auth-state"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        authenticate(in: app, credentials: credentials)
        try runPlaybackScenario(
            in: app,
            scenario: "live-login",
            preferredKinds: ["continueWatching", "nextUp", "movies", "shows"]
        )
    }

    private func ensureAuthenticated(in app: XCUIApplication) throws {
        if waitForHome(in: app) {
            return
        }

        guard let credentials = loadLiveCredentials() else {
            throw XCTSkip("No authenticated session found on the simulator and REELFIN_TEST_SERVER_URL / REELFIN_TEST_USERNAME / REELFIN_TEST_PASSWORD are not set.")
        }

        authenticate(in: app, credentials: credentials)
        XCTAssertTrue(waitForHome(in: app))
    }

    private func authenticate(in app: XCUIApplication, credentials: LiveCredentials) {
        advanceThroughOnboardingIfNeeded(app)

        let serverField = app.textFields["login_server_field"].firstMatch
        XCTAssertTrue(serverField.waitForExistence(timeout: 10))
        replaceText(in: serverField, with: credentials.serverURL)

        let continueButton = app.buttons["login_server_continue"].firstMatch
        XCTAssertTrue(continueButton.exists)
        logTap("continue_from_server")
        submitServerEntry(in: app, field: serverField, continueButton: continueButton)

        XCTAssertTrue(waitForCredentialsStage(in: app, timeout: 12))

        let usernameField = app.textFields["login_username_field"].firstMatch.exists
            ? app.textFields["login_username_field"].firstMatch
            : app.textFields.firstMatch
        XCTAssertTrue(usernameField.waitForExistence(timeout: 12))
        replaceText(in: usernameField, with: credentials.username)

        let passwordField = app.secureTextFields["login_password_field"].firstMatch
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5))
        replaceText(in: passwordField, with: credentials.password)

        let signInButton = app.buttons["login_sign_in"].firstMatch
        XCTAssertTrue(signInButton.exists)
        logTap("sign_in")
        signInButton.tap()
    }

    private func runPlaybackScenario(
        in app: XCUIApplication,
        scenario: String,
        preferredKinds: [String]
    ) throws {
        XCTAssertTrue(waitForHome(in: app))

        let targetCard = try selectCard(in: app, preferredKinds: preferredKinds, scenario: scenario)
        logTap("open_\(scenario)_card:\(targetCard.identifier)")
        targetCard.tap()

        let actionButton = try playbackActionButton(in: app)
        captureScreenshot(of: app, name: "\(scenario)-detail-before-play")
        logTap("tap_\(scenario)_\(actionButton.label.lowercased())")
        actionButton.tap()

        let playerScreen = app.otherElements["native_player_screen"].firstMatch
        XCTAssertTrue(playerScreen.waitForExistence(timeout: 15))
        sleep(2)
        captureScreenshot(of: app, name: "\(scenario)-player-after-play")
    }

    private func selectCard(
        in app: XCUIApplication,
        preferredKinds: [String],
        scenario: String
    ) throws -> XCUIElement {
        for kind in preferredKinds {
            let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "media_card_button_\(kind)_")
            let candidate = app.buttons.matching(predicate).firstMatch
            if candidate.waitForExistence(timeout: 4) {
                return candidate
            }
        }

        let fallback = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "media_card_button_")
        ).firstMatch
        if fallback.waitForExistence(timeout: 10) {
            return fallback
        }

        throw XCTSkip("No playable media card found for \(scenario).")
    }

    private func playbackActionButton(in app: XCUIApplication) throws -> XCUIElement {
        let identifiedButton = app.buttons["detail_play_button"].firstMatch
        if identifiedButton.waitForExistence(timeout: 8) {
            return identifiedButton
        }

        for prefix in ["Resume", "Play", "Play Again"] {
            let predicate = NSPredicate(format: "label BEGINSWITH[c] %@", prefix)
            let button = app.buttons.matching(predicate).firstMatch
            if button.waitForExistence(timeout: prefix == "Resume" ? 4 : 12) {
                return button
            }
        }

        throw XCTSkip("No Play or Resume button found on detail.")
    }

    private func waitForHome(in app: XCUIApplication) -> Bool {
        let homeTab = app.tabBars.buttons["Home"].firstMatch
        if homeTab.waitForExistence(timeout: 12) {
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

        for _ in 0 ..< 6 {
            let onboardingButton = app.buttons["onboarding_primary_cta"].firstMatch
            XCTAssertTrue(onboardingButton.waitForExistence(timeout: 5))
            onboardingButton.tap()

            if serverField.waitForExistence(timeout: 1.5) {
                return
            }
        }

        XCTFail("Expected onboarding to advance to server entry.")
    }

    private func submitServerEntry(in app: XCUIApplication, field: XCUIElement, continueButton: XCUIElement) {
        field.tap()
        field.typeText("\n")

        if app.textFields["login_username_field"].firstMatch.waitForExistence(timeout: 1.5) {
            return
        }

        if app.buttons["login_sign_in"].firstMatch.waitForExistence(timeout: 2) ||
            app.secureTextFields["login_password_field"].firstMatch.exists
        {
            return
        }

        if continueButton.isHittable {
            continueButton.tap()
            return
        }

        app.swipeUp()
        if continueButton.waitForExistence(timeout: 2), continueButton.isHittable {
            continueButton.tap()
            return
        }

        continueButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func waitForCredentialsStage(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if app.otherElements["login_credentials_sheet"].firstMatch.exists ||
                app.textFields["login_username_field"].firstMatch.exists ||
                app.secureTextFields["login_password_field"].firstMatch.exists ||
                app.buttons["login_sign_in"].firstMatch.exists
            {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return false
    }

    private func loadLiveCredentials() -> LiveCredentials? {
        let environment = ProcessInfo.processInfo.environment
        guard
            let serverURL = environment["REELFIN_TEST_SERVER_URL"],
            let username = environment["REELFIN_TEST_USERNAME"],
            let password = environment["REELFIN_TEST_PASSWORD"],
            !serverURL.isEmpty,
            !username.isEmpty,
            !password.isEmpty
        else {
            return nil
        }

        return LiveCredentials(
            serverURL: serverURL,
            username: username,
            password: password
        )
    }

    private func requireLiveCredentials() throws -> LiveCredentials {
        guard let credentials = loadLiveCredentials() else {
            throw XCTSkip("Set REELFIN_TEST_SERVER_URL / REELFIN_TEST_USERNAME / REELFIN_TEST_PASSWORD to run the live UI smoke test.")
        }

        return credentials
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

    private func captureScreenshot(of app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("[UI-SCREENSHOT] \(name)")
    }

    private func logTap(_ step: String) {
        print("[UI-TAP] \(step)")
    }
}
