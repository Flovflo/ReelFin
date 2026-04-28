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
            "-reelfin-onboarding-page",
            "5",
            "-reelfin-ui-reset-auth-state"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        if !waitForHome(in: app) {
            authenticate(in: app, credentials: credentials)
        }
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
        XCTAssertTrue(openCardAndWaitForDetail(targetCard, in: app))

        let actionButton = try playbackActionButton(in: app)
        captureScreenshot(of: app, name: "\(scenario)-detail-before-play")
        logTap("tap_\(scenario)_\(actionButton.label.lowercased())")
        tapElement(actionButton)

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
        if let explicitItemID = explicitDirectPlayItemID() {
            let explicitCandidate = app.buttons.matching(
                NSPredicate(format: "identifier CONTAINS %@", explicitItemID)
            ).firstMatch
            if explicitCandidate.waitForExistence(timeout: 8) {
                return explicitCandidate
            }
        }

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

    private func openCardAndWaitForDetail(_ card: XCUIElement, in app: XCUIApplication) -> Bool {
        for attempt in 0 ..< 3 {
            tapElement(card)
            if waitForDetail(in: app, timeout: attempt == 0 ? 5 : 7) {
                return true
            }
        }
        return false
    }

    private func waitForDetail(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let carousel = app.scrollViews["detail_ios_top_carousel"].firstMatch
        let favoriteButton = app.buttons["detail_favorite_button"].firstMatch
        let watchedButton = app.buttons["detail_watched_button"].firstMatch

        while Date() < deadline {
            if carousel.exists || favoriteButton.exists || watchedButton.exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return carousel.exists || favoriteButton.exists || watchedButton.exists
    }

    private func explicitDirectPlayItemID() -> String? {
        var environment = ProcessInfo.processInfo.environment
        loadEnvFile().forEach { key, value in
            environment[key] = environment[key] ?? value
        }
        guard let raw = environment["TEST_DIRECTPLAY_MP4_ITEM_ID"], !raw.isEmpty else { return nil }
        let patterns = [
            #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#,
            #"[0-9a-fA-F]{32}"#
        ]
        for pattern in patterns {
            if let range = raw.range(of: pattern, options: .regularExpression) {
                return raw[range].filter { $0 != "-" }.lowercased()
            }
        }
        return nil
    }

    private func tapElement(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
            return
        }

        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func playbackActionButton(in app: XCUIApplication) throws -> XCUIElement {
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
        if serverField.waitForExistence(timeout: 3) {
            return
        }

        for _ in 0 ..< 6 {
            let onboardingButton = app.buttons["onboarding_primary_cta"].firstMatch
            if onboardingButton.waitForExistence(timeout: 3) {
                tapElement(onboardingButton)
            }

            if serverField.waitForExistence(timeout: 2) {
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
        var environment = ProcessInfo.processInfo.environment
        loadEnvFile().forEach { key, value in
            environment[key] = environment[key] ?? value
        }
        guard
            let serverURL = environment["REELFIN_TEST_SERVER_URL"] ?? environment["JELLYFIN_BASE_URL"],
            let username = environment["REELFIN_TEST_USERNAME"] ?? environment["JELLYFIN_USERNAME"],
            let password = environment["REELFIN_TEST_PASSWORD"] ?? environment["JELLYFIN_PASSWORD"],
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

    private func loadEnvFile() -> [String: String] {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let envURL = repoRoot.appendingPathComponent(".artifacts/secrets/reelfin-e2e.env")
        guard let content = try? String(contentsOf: envURL, encoding: .utf8) else { return [:] }

        var values: [String: String] = [:]
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else { continue }
            var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               let quote = value.first,
               quote == value.last,
               quote == "\"" || quote == "'" {
                value.removeFirst()
                value.removeLast()
            }
            values[String(key)] = String(value)
        }
        return values
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
