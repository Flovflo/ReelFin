import XCTest

final class PlaybackLiveSmokeUITests: XCTestCase {
    private struct LiveCredentials {
        let serverURL: String
        let username: String
        let password: String
    }

    private enum PlaybackLiveSmokeError: Error, LocalizedError {
        case explicitTargetNotVisible(String)
        case requiredControlMissing(String)
        case requiredMenuMissing(String)

        var errorDescription: String? {
            switch self {
            case .explicitTargetNotVisible(let itemID):
                return "Explicit live UI target item \(itemID.prefix(8)) was not visible in Home; refusing fallback playback."
            case .requiredControlMissing(let label):
                return "Expected required live player control '\(label)' to be visible."
            case .requiredMenuMissing(let identifier):
                return "Expected required live player menu '\(identifier)' to open."
            }
        }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testExistingSessionMoviePlaybackSmoke() throws {
        let app = XCUIApplication()
        configureLivePlaybackLaunchEnvironment(app)
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
        configureLivePlaybackLaunchEnvironment(app)
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
        configureLivePlaybackLaunchEnvironment(app)
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

        if shouldOpenExplicitTargetDirectly() {
            XCTAssertTrue(
                waitForDetail(in: app, timeout: 45),
                "Expected the app to open the explicit live UI target detail."
            )
        } else {
            let targetCard = try selectCard(in: app, preferredKinds: preferredKinds, scenario: scenario)
            logTap("open_\(scenario)_card:\(targetCard.identifier)")
            XCTAssertTrue(openCardAndWaitForDetail(targetCard, in: app))
        }

        let actionButton = try playbackActionButton(in: app)
        captureScreenshot(of: app, name: "\(scenario)-detail-before-play")
        logTap("tap_\(scenario)_\(actionButton.label.lowercased())")
        tapElement(actionButton)

        let playerScreen = app.otherElements["native_player_screen"].firstMatch
        XCTAssertTrue(playerScreen.waitForExistence(timeout: 15))
        let playerChromeSurface = chromeInteractionSurface(in: app, fallback: playerScreen)
        observePlaybackStartup()
        try exercisePlayerControls(in: app, playerScreen: playerChromeSurface)
        captureScreenshot(of: app, name: "\(scenario)-player-after-play")
        try dismissPlayer(in: app, playerScreen: playerChromeSurface)
    }

    private func exercisePlayerControls(in app: XCUIApplication, playerScreen: XCUIElement) throws {
        let requireCustomControls = shouldRequireCustomPlayerControls()
        revealPlayerChrome(playerScreen)
        if tapPlaybackButton(
            in: app,
            identifiers: ["native_player_play_pause_button"],
            labels: ["Pause", "Play/Pause"],
            timeout: 5,
            logLabel: "pause_playback"
        ) {
            resumePlayback(in: app, playerScreen: playerScreen)
        } else if requireCustomControls {
            throw PlaybackLiveSmokeError.requiredControlMissing("pause_playback")
        }

        revealPlayerChrome(playerScreen)
        if requireCustomControls {
            guard tapPlaybackButton(
                in: app,
                identifiers: ["native_player_seek_forward_10"],
                labels: ["Avancer de 10 secondes"],
                timeout: 5,
                logLabel: "seek_forward_10"
            ) else {
                throw PlaybackLiveSmokeError.requiredControlMissing("seek_forward_10")
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        } else if tapPlaybackButton(
            in: app,
            identifiers: ["native_player_seek_forward_10"],
            labels: ["Avancer de 10 secondes"],
            timeout: 2,
            logLabel: "seek_forward_10"
        ) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }

        revealPlayerChrome(playerScreen)
        if requireCustomControls {
            guard tapPlaybackButton(
                in: app,
                identifiers: ["native_player_seek_backward_10"],
                labels: ["Reculer de 10 secondes"],
                timeout: 5,
                logLabel: "seek_backward_10"
            ) else {
                throw PlaybackLiveSmokeError.requiredControlMissing("seek_backward_10")
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        } else if tapPlaybackButton(
            in: app,
            identifiers: ["native_player_seek_backward_10"],
            labels: ["Reculer de 10 secondes"],
            timeout: 2,
            logLabel: "seek_backward_10"
        ) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }

        try exerciseTrackMenu(
            in: app,
            playerScreen: playerScreen,
            buttonIdentifiers: ["native_player_audio_button"],
            buttonLabel: "Audio",
            menuIdentifier: "native_player_audio_menu",
            preferredOptionLabel: nil,
            required: requireCustomControls
        )
        try exerciseTrackMenu(
            in: app,
            playerScreen: playerScreen,
            buttonIdentifiers: ["native_player_subtitles_button"],
            buttonLabel: "Sous-titres",
            menuIdentifier: "native_player_subtitles_menu",
            preferredOptionLabel: "Off",
            required: requireCustomControls
        )
    }

    private func exerciseTrackMenu(
        in app: XCUIApplication,
        playerScreen: XCUIElement,
        buttonIdentifiers: [String],
        buttonLabel: String,
        menuIdentifier: String,
        preferredOptionLabel: String?,
        required: Bool
    ) throws {
        revealPlayerChrome(playerScreen)
        guard tapPlaybackButton(
            in: app,
            identifiers: buttonIdentifiers,
            labels: [buttonLabel],
            timeout: 3,
            logLabel: "open_\(buttonLabel.lowercased())_menu"
        ) else {
            if required {
                throw PlaybackLiveSmokeError.requiredControlMissing(buttonLabel)
            }
            return
        }

        let menu = firstExistingElement(in: app, identifier: menuIdentifier)
        guard menu.waitForExistence(timeout: 2) else {
            if required {
                throw PlaybackLiveSmokeError.requiredMenuMissing(menuIdentifier)
            }
            return
        }

        if let preferredOptionLabel {
            let option = app.buttons[preferredOptionLabel].firstMatch
            if option.waitForExistence(timeout: 2) {
                logTap("select_\(buttonLabel.lowercased())_\(preferredOptionLabel.lowercased())")
                tapElement(option)
            }
        } else {
            let optionButtons = menu.buttons.allElementsBoundByIndex.filter { $0.exists }
            if let option = optionButtons.dropFirst().first ?? optionButtons.first {
                logTap("select_\(buttonLabel.lowercased())_track")
                tapElement(option)
                RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            } else {
                revealPlayerChrome(playerScreen)
            }
        }
    }

    private func dismissPlayer(in app: XCUIApplication, playerScreen: XCUIElement) throws {
        revealPlayerChrome(playerScreen)
        guard tapPlaybackButton(
            in: app,
            identifiers: ["native_player_close_button"],
            labels: ["Fermer le lecteur"],
            timeout: 3,
            logLabel: "close_player"
        ) else {
            if shouldRequireCustomPlayerControls() {
                throw PlaybackLiveSmokeError.requiredControlMissing("close_player")
            }
            return
        }
        _ = waitForDetail(in: app, timeout: 5)
    }

    private func revealPlayerChrome(_ playerScreen: XCUIElement) {
        if playerScreen.exists {
            playerScreen.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func chromeInteractionSurface(in app: XCUIApplication, fallback: XCUIElement) -> XCUIElement {
        let nativeEngineSurface = app.otherElements["native_engine_player_screen"].firstMatch
        if nativeEngineSurface.exists {
            return nativeEngineSurface
        }
        return fallback
    }

    private func resumePlayback(in app: XCUIApplication, playerScreen: XCUIElement) {
        revealPlayerChrome(playerScreen)
        if tapPlaybackButton(
            in: app,
            identifiers: ["native_player_play_pause_button"],
            labels: ["Lire", "Play", "Play/Pause"],
            timeout: 5,
            logLabel: "resume_playback"
        ) {
            return
        }

        XCTFail("Expected a player resume control after pausing playback.")
    }

    @discardableResult
    private func tapPlaybackButton(
        in app: XCUIApplication,
        identifiers: [String] = [],
        labels: [String],
        timeout: TimeInterval,
        logLabel: String
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for identifier in identifiers {
                let element = firstExistingElement(in: app, identifier: identifier)
                if element.exists {
                    logTap(logLabel)
                    tapElement(element)
                    return true
                }
            }
            for label in labels {
                let element = firstExistingElement(in: app, label: label)
                if element.exists {
                    logTap(logLabel)
                    tapElement(element)
                    return true
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        return false
    }

    private func firstExistingButton(
        in app: XCUIApplication,
        identifiers: [String],
        labels: [String]
    ) -> XCUIElement {
        for identifier in identifiers {
            let candidate = firstExistingElement(in: app, identifier: identifier)
            if candidate.exists {
                return candidate
            }
        }
        for label in labels {
            let candidate = firstExistingElement(in: app, label: label)
            if candidate.exists {
                return candidate
            }
        }
        if let identifier = identifiers.first {
            return app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        }
        return app.buttons[labels.first ?? ""].firstMatch
    }

    private func firstExistingElement(in app: XCUIApplication, identifier: String) -> XCUIElement {
        let button = app.buttons[identifier].firstMatch
        if button.exists {
            return button
        }
        return app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func firstExistingElement(in app: XCUIApplication, label: String) -> XCUIElement {
        let button = app.buttons[label].firstMatch
        if button.exists {
            return button
        }
        let predicate = NSPredicate(format: "label == %@", label)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    @discardableResult
    private func tapIfExists(_ element: XCUIElement, timeout: TimeInterval, label: String) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        logTap(label)
        tapElement(element)
        return true
    }

    private func tapRequired(_ element: XCUIElement, timeout: TimeInterval, label: String) throws {
        guard element.waitForExistence(timeout: timeout) else {
            throw PlaybackLiveSmokeError.requiredControlMissing(label)
        }
        logTap(label)
        tapElement(element)
    }

    private func observePlaybackStartup() {
        let seconds = playbackObservationSeconds()
        guard seconds > 0 else { return }
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func playbackObservationSeconds() -> TimeInterval {
        let raw = loadEnvironmentValues()["REELFIN_LIVE_UI_OBSERVE_SECONDS"] ?? "12"
        guard let seconds = TimeInterval(raw) else { return 12 }
        return min(max(seconds, 0), 120)
    }

    private func shouldRequireCustomPlayerControls() -> Bool {
        let value = loadEnvironmentValues()["REELFIN_LIVE_UI_EXPECT_CUSTOM_CONTROLS"] ?? ""
        return ["1", "true", "yes", "on"].contains(value.lowercased())
    }

    private func shouldOpenExplicitTargetDirectly() -> Bool {
        let value = loadEnvironmentValues()["REELFIN_LIVE_UI_OPEN_TARGET_DIRECTLY"] ?? ""
        return ["1", "true", "yes", "on"].contains(value.lowercased())
    }

    private func selectCard(
        in app: XCUIApplication,
        preferredKinds: [String],
        scenario: String
    ) throws -> XCUIElement {
        if let explicitItemID = explicitTargetItemID() {
            let explicitCandidate = app.buttons.matching(
                NSPredicate(format: "identifier CONTAINS %@", explicitItemID)
            ).firstMatch
            if explicitCandidate.waitForExistence(timeout: 30) {
                return explicitCandidate
            }
            throw PlaybackLiveSmokeError.explicitTargetNotVisible(explicitItemID)
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
        let identifier = card.identifier
        for attempt in 0 ..< 3 {
            let currentCard = identifier.isEmpty ? card : app.buttons[identifier].firstMatch
            guard bringCardIntoViewport(currentCard, in: app) else { continue }
            currentCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if waitForDetail(in: app, timeout: attempt == 0 ? 5 : 7) {
                return true
            }
        }
        return false
    }

    private func bringCardIntoViewport(_ card: XCUIElement, in app: XCUIApplication) -> Bool {
        guard card.exists else { return false }
        let windowFrame = app.windows.firstMatch.exists
            ? app.windows.firstMatch.frame
            : CGRect(origin: .zero, size: XCUIScreen.main.screenshot().image.size)

        for _ in 0 ..< 8 {
            let cardFrame = card.frame
            if windowFrame.contains(CGPoint(x: cardFrame.midX, y: cardFrame.midY)) {
                return true
            }
            if cardFrame.midY > windowFrame.maxY {
                app.swipeUp()
            } else if cardFrame.midY < windowFrame.minY {
                app.swipeDown()
            } else if cardFrame.midX > windowFrame.maxX,
                      let row = horizontalScrollView(containingY: cardFrame.midY, in: app) {
                row.swipeLeft()
            } else if cardFrame.midX < windowFrame.minX,
                      let row = horizontalScrollView(containingY: cardFrame.midY, in: app) {
                row.swipeRight()
            } else {
                return false
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        let finalFrame = card.frame
        return windowFrame.contains(CGPoint(x: finalFrame.midX, y: finalFrame.midY))
    }

    private func horizontalScrollView(containingY yPosition: CGFloat, in app: XCUIApplication) -> XCUIElement? {
        let candidates = app.scrollViews.allElementsBoundByIndex
        let maximumRowHeight = app.windows.firstMatch.exists
            ? app.windows.firstMatch.frame.height * 0.6
            : CGFloat.greatestFiniteMagnitude
        return candidates.first { scrollView in
            let frame = scrollView.frame
            return frame.minY <= yPosition &&
                yPosition <= frame.maxY &&
                frame.height < maximumRowHeight
        }
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

    private func explicitTargetItemID() -> String? {
        let environment = loadEnvironmentValues()
        for key in ["REELFIN_LIVE_UI_TARGET_ITEM_ID", "TEST_DIRECTPLAY_MP4_ITEM_ID"] {
            guard let raw = environment[key], !raw.isEmpty else { continue }
            if let normalized = normalizedItemID(raw) {
                return normalized
            }
        }
        return nil
    }

    private func normalizedItemID(_ raw: String) -> String? {
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
        let identifiedPrimaryAction = app.buttons["detail_primary_play_button"].firstMatch
        if identifiedPrimaryAction.waitForExistence(timeout: 12) {
            return identifiedPrimaryAction
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
        let environment = loadEnvironmentValues()
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

    private func configureLivePlaybackLaunchEnvironment(_ app: XCUIApplication) {
        let environment = loadEnvironmentValues()
        if shouldOpenExplicitTargetDirectly(), let targetItemID = explicitTargetItemID() {
            app.launchArguments += ["-reelfin-live-ui-open-target", targetItemID]
        }
        for key in [
            "REELFIN_LIVE_UI_TARGET_ITEM_ID",
            "REELFIN_LIVE_UI_OPEN_TARGET_DIRECTLY",
            "REELFIN_PLAYER_DEEP_EVIDENCE",
            "REELFIN_PLAYER_DEEP_EVIDENCE_RESET"
        ] {
            guard let value = environment[key], !value.isEmpty else { continue }
            app.launchEnvironment[key] = value
        }
    }

    private func loadEnvironmentValues() -> [String: String] {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        var values = readEnvFile(repoRoot.appendingPathComponent(".artifacts/secrets/reelfin-e2e.env"))
        ProcessInfo.processInfo.environment.forEach { key, value in
            values[key] = value
        }
        let liveUITargetURL = repoRoot.appendingPathComponent(".artifacts/player-e2e/live-ui-target.env")
        if isFreshLiveUITargetEnv(liveUITargetURL) {
            readEnvFile(liveUITargetURL).forEach { key, value in
                values[key] = value
            }
        }
        return values
    }

    private func readEnvFile(_ envURL: URL) -> [String: String] {
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

    private func isFreshLiveUITargetEnv(_ envURL: URL) -> Bool {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: envURL.path),
            let modifiedAt = attributes[.modificationDate] as? Date
        else {
            return false
        }
        return Date().timeIntervalSince(modifiedAt) <= 20 * 60
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
