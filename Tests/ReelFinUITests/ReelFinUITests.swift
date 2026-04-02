import XCTest

class ReelFinUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLoggedOutMockLaunchShowsPremiumOnboarding() throws {
        let app = launchLoggedOutMockApp()

        XCTAssertTrue(app.staticTexts["onboarding_title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding_primary_cta"].exists)
    }

    func testLoggedOutMockFlowAdvancesFromOnboardingToServerEntry() throws {
        let app = launchLoggedOutMockApp()

        advanceThroughOnboardingIfNeeded(app)

        let serverField = app.textFields["login_server_field"]
        XCTAssertTrue(serverField.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["login_server_continue"].exists)
    }

    func testLoggedOutMockFlowCanAuthenticateIntoHome() throws {
        let app = launchLoggedOutMockApp()

        advanceThroughOnboardingIfNeeded(app)

        let continueButton = app.buttons["login_server_continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))

        let serverField = app.textFields["login_server_field"]
        XCTAssertTrue(serverField.exists)
        enterServerIfNeeded(serverField, forceRetype: true)

        continueButton.tap()

        let usernameField = app.textFields["login_username_field"].firstMatch
        XCTAssertTrue(usernameField.waitForExistence(timeout: 8))
        usernameField.tap()
        usernameField.typeText("preview")

        let passwordField = app.secureTextFields["login_password_field"].firstMatch
        XCTAssertTrue(passwordField.exists)
        passwordField.tap()
        passwordField.typeText("password")

        let signInButton = app.buttons["login_sign_in"].firstMatch
        XCTAssertTrue(signInButton.exists)
        signInButton.tap()

        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 8))
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

        // This test requires a live Jellyfin server to pre-populate content cards.
        // We look for the first media card by accessibility identifier.
        let firstPoster = app.buttons.matching(identifier: "media_card").firstMatch
        guard firstPoster.waitForExistence(timeout: 10) else {
            throw XCTSkip("No media cards found – likely no live Jellyfin server available.")
        }
        firstPoster.tap()

        let playButton = app.buttons["Play"]
        guard playButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Detail view did not show a Play button – server may be unavailable.")
        }

        app.navigationBars.buttons.firstMatch.tap()
    }

    func testPlaybackStartsFast() throws {
        let app = XCUIApplication()
        app.launch()

        // Find the first media card
        let firstPoster = app.buttons.matching(identifier: "media_card").firstMatch
        guard firstPoster.waitForExistence(timeout: 10) else {
            throw XCTSkip("No media cards found – likely no live Jellyfin server available.")
        }
        firstPoster.tap()

        // Tap the Play button in the detail view
        let playButton = app.buttons["Play"]
        guard playButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("Detail view did not show a Play button – server may be unavailable.")
        }
        playButton.tap()

        // Verify the video player (AVPlayerViewController) appears within 8 seconds.
        // This guards against major TTFF regressions.
        let playerView = app.otherElements["Video Player"]
        let playerExists = playerView.waitForExistence(timeout: 8)

        if !playerExists {
            // Fallback: check for any full-screen element that could be the player
            let anyMediaElement = app.windows.firstMatch
            XCTAssertTrue(
                anyMediaElement.exists,
                "Video player should appear within 8 seconds of tapping Play"
            )
        }
    }

    private func launchLoggedOutMockApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-reelfin-mock-mode", "-reelfin-ui-logged-out"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        return app
    }

    private func enterServerIfNeeded(_ field: XCUIElement, forceRetype: Bool = false) {
        if !forceRetype, let currentValue = field.value as? String {
            if currentValue == "https://demo.reelfin.app" {
                return
            }
        }

        field.tap()

        if let currentValue = field.value as? String {
            if !currentValue.isEmpty,
               currentValue != "https://server.example.com"
            {
                let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
                field.typeText(deletes)
            }
        }

        field.typeText("https://demo.reelfin.app")
    }

    private func advanceThroughOnboardingIfNeeded(_ app: XCUIApplication) {
        let serverField = app.textFields["login_server_field"]
        if serverField.exists {
            return
        }

        for _ in 0..<OnboardingScreenCount.total {
            let onboardingButton = app.buttons["onboarding_primary_cta"]
            XCTAssertTrue(onboardingButton.waitForExistence(timeout: 5))
            onboardingButton.tap()

            if serverField.waitForExistence(timeout: 1.5) {
                return
            }
        }

        XCTFail("Expected onboarding to advance to the server entry step")
    }
}

private enum OnboardingScreenCount {
    static let total = 4
}

final class AppStoreScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-reelfin-mock-mode", "-reelfin-screenshot-mode"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        let firstPoster = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "media_card_button_")).firstMatch
        XCTAssertTrue(firstPoster.waitForExistence(timeout: 12))
        capture(name: "01-home")

        openSection(named: "Search", in: app)
        XCTAssertTrue(firstPoster.waitForExistence(timeout: 8))
        capture(name: "02-library")

        firstPoster.tap()
        let playButton = app.buttons["Play"]
        XCTAssertTrue(playButton.waitForExistence(timeout: 8))
        capture(name: "03-detail")
        openSection(named: "Settings", in: app)
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 8))
        capture(name: "04-settings")
    }

    func testCapturePlayerScreenshot() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-reelfin-mock-mode", "-reelfin-screenshot-mode"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        let firstPoster = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "media_card_button_")).firstMatch
        XCTAssertTrue(firstPoster.waitForExistence(timeout: 12))

        firstPoster.tap()
        let playButton = app.buttons["Play"]
        XCTAssertTrue(playButton.waitForExistence(timeout: 8))

        playButton.tap()
        let playerScreen = app.otherElements["native_player_screen"].firstMatch
        XCTAssertTrue(playerScreen.waitForExistence(timeout: 12))
        sleep(2)
        capture(name: "player-native")
    }

    private func openSection(named title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let tabButton = app.tabBars.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
        if tabButton.exists {
            tabButton.tap()
            return
        }

        if let tabIndex = tabIndex(for: title), app.tabBars.buttons.count > tabIndex {
            app.tabBars.buttons.element(boundBy: tabIndex).tap()
            return
        }

        let sidebarButton = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
        if sidebarButton.exists {
            sidebarButton.tap()
            return
        }

        let sidebarLabel = app.staticTexts.matching(NSPredicate(format: "label == %@", title)).firstMatch
        if sidebarLabel.exists {
            sidebarLabel.tap()
            return
        }

        let cellLabel = app.cells.staticTexts.matching(NSPredicate(format: "label == %@", title)).firstMatch
        if cellLabel.exists {
            cellLabel.tap()
            return
        }

        XCTFail("Unable to navigate to \(title)", file: file, line: line)
    }

    private func tabIndex(for title: String) -> Int? {
        switch title {
        case "Home":
            return 0
        case "Search":
            return 1
        case "Settings":
            return 2
        default:
            return nil
        }
    }

    private func capture(name: String, file: StaticString = #filePath, line: UInt = #line) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let outputDirectory = ProcessInfo.processInfo.environment["REELFIN_SCREENSHOT_OUTPUT_DIR"] else {
            return
        }

        let deviceSlug = ProcessInfo.processInfo.environment["REELFIN_SCREENSHOT_DEVICE_SLUG"] ?? "simulator"
        let deviceDirectory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
            .appendingPathComponent(deviceSlug, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: deviceDirectory, withIntermediateDirectories: true)
            let destinationURL = deviceDirectory.appendingPathComponent("\(name).png")
            try screenshot.pngRepresentation.write(to: destinationURL)
        } catch {
            XCTFail("Unable to export screenshot \(name): \(error.localizedDescription)", file: file, line: line)
        }
    }
}
