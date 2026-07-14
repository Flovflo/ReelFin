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

    func testLandingLaunchesWithStableIdentityLabelsAndQuickConnectFocus() {
        let app = launchLogin(phase: "landing")
        let stage = app.otherElements["tv_login_stage_landing"]
        let quickConnect = app.buttons["tv_login_quick_connect"]

        XCTAssertTrue(stage.waitForExistence(timeout: 8))
        XCTAssertEqual(stage.label, "Connect your server")
        XCTAssertTrue(quickConnect.waitForExistence(timeout: 3))
        XCTAssertEqual(quickConnect.label, "Quick Connect")
        XCTAssertEqual(app.buttons["tv_login_use_password"].label, "Use Password")
        XCTAssertEqual(app.buttons["tv_login_choose_server"].label, "Choose Another Server")
        XCTAssertTrue(waitForFocus(quickConnect))
    }

    func testServerLaunchesWithStableIdentityLabelsAndAddressFocus() {
        let app = launchLogin(phase: "server")
        let stage = app.otherElements["tv_login_stage_server"]
        let serverField = app.textFields["tv_login_server_field"]

        XCTAssertTrue(stage.waitForExistence(timeout: 8))
        XCTAssertEqual(stage.label, "Enter your server")
        XCTAssertTrue(serverField.waitForExistence(timeout: 3))
        XCTAssertEqual(serverField.label, "Jellyfin server address")
        XCTAssertEqual(app.buttons["tv_login_server_back"].label, "Back")
        XCTAssertEqual(app.buttons["tv_login_server_primary"].label, "Get Code")
        XCTAssertEqual(app.buttons["tv_login_server_alternate"].label, "Use Password")
        XCTAssertTrue(waitForFocus(serverField))
    }

    func testCredentialsLaunchesWithStableIdentityLabelsAndUsernameFocus() {
        let app = launchLogin(phase: "credentials", path: "credentials")
        let stage = app.otherElements["tv_login_stage_credentials"]
        let usernameField = app.textFields["tv_login_username_field"]
        let passwordField = app.secureTextFields["tv_login_password_field"]

        XCTAssertTrue(stage.waitForExistence(timeout: 8))
        XCTAssertEqual(stage.label, "Sign in")
        XCTAssertTrue(usernameField.waitForExistence(timeout: 3))
        XCTAssertTrue(passwordField.waitForExistence(timeout: 3))
        XCTAssertEqual(usernameField.label, "Jellyfin username")
        XCTAssertEqual(passwordField.label, "Jellyfin password")
        XCTAssertEqual(app.buttons["tv_login_credentials_back"].label, "Back")
        XCTAssertEqual(app.buttons["tv_login_credentials_submit"].label, "Sign In")
        XCTAssertEqual(app.buttons["tv_login_credentials_quick_connect"].label, "Quick Connect")
        XCTAssertTrue(waitForFocus(usernameField))
    }

    func testQuickConnectLaunchesWithStableIdentityAndPasswordActionFocus() {
        let app = launchLogin(phase: "quickConnect")
        let stage = app.otherElements["tv_login_stage_quick_connect"]
        let usePassword = app.buttons["tv_login_quick_connect_use_password"]

        XCTAssertTrue(stage.waitForExistence(timeout: 8))
        XCTAssertEqual(stage.label, "Approve on another device")
        XCTAssertTrue(usePassword.waitForExistence(timeout: 3))
        XCTAssertEqual(usePassword.label, "Use Password Instead")
        XCTAssertTrue(waitForFocus(usePassword))
    }

    func testSubmittingAndSuccessExposeStableStageIdentity() {
        let submittingApp = launchLogin(phase: "submitting", path: "credentials")
        let submitting = submittingApp.otherElements["tv_login_stage_submitting"]
        XCTAssertTrue(submitting.waitForExistence(timeout: 8))
        XCTAssertEqual(submitting.label, "Signing in")

        let successApp = launchLogin(phase: "success")
        let success = successApp.otherElements["tv_login_stage_success"]
        XCTAssertTrue(success.waitForExistence(timeout: 8))
        XCTAssertEqual(success.label, "Connected")
    }

    func testMenuRoutesServerToLandingAndRestoresQuickConnectFocus() {
        let app = launchLogin(phase: "server")
        let serverField = app.textFields["tv_login_server_field"]
        XCTAssertTrue(serverField.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForFocus(serverField))

        XCUIRemote.shared.press(.menu)

        let landing = app.otherElements["tv_login_stage_landing"]
        let quickConnect = app.buttons["tv_login_quick_connect"]
        XCTAssertTrue(landing.waitForExistence(timeout: 3))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(waitForFocus(quickConnect))
    }

    func testMenuOnLandingIsConsumedWithoutChangingFocus() {
        let app = launchLogin(phase: "landing")
        let quickConnect = app.buttons["tv_login_quick_connect"]
        XCTAssertTrue(quickConnect.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForFocus(quickConnect))

        XCUIRemote.shared.press(.menu)

        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.otherElements["tv_login_stage_landing"].exists)
        XCTAssertTrue(waitForFocus(quickConnect))
    }

    func testMenuRoutesCredentialsToServerAndRestoresAddressFocus() {
        let app = launchLogin(phase: "credentials", path: "credentials")
        let username = app.textFields["tv_login_username_field"]
        XCTAssertTrue(username.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForFocus(username))

        XCUIRemote.shared.press(.menu)

        let server = app.otherElements["tv_login_stage_server"]
        let serverField = app.textFields["tv_login_server_field"]
        XCTAssertTrue(server.waitForExistence(timeout: 3))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(waitForFocus(serverField))
    }

    func testVisibleBackActionsMatchMenuDestinations() {
        let serverApp = launchLogin(phase: "server")
        let serverField = serverApp.textFields["tv_login_server_field"]
        let serverPrimary = serverApp.buttons["tv_login_server_primary"]
        let serverBack = serverApp.buttons["tv_login_server_back"]
        XCTAssertTrue(serverField.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForFocus(serverField))
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForFocus(serverPrimary))
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(waitForFocus(serverBack))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(serverApp.otherElements["tv_login_stage_landing"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForFocus(serverApp.buttons["tv_login_quick_connect"]))

        let credentialsApp = launchLogin(
            phase: "credentials",
            path: "credentials",
            extraArguments: [
                "-reelfin-tv-login-username", "viewer",
                "-reelfin-tv-login-password", "password"
            ]
        )
        let username = credentialsApp.textFields["tv_login_username_field"]
        let password = credentialsApp.secureTextFields["tv_login_password_field"]
        let submit = credentialsApp.buttons["tv_login_credentials_submit"]
        let credentialsBack = credentialsApp.buttons["tv_login_credentials_back"]
        XCTAssertTrue(username.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForFocus(username))
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForFocus(password))
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForFocus(submit))
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(waitForFocus(credentialsBack))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(credentialsApp.otherElements["tv_login_stage_server"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForFocus(credentialsApp.textFields["tv_login_server_field"]))
    }

    func testFailedCredentialsJourneyRestoresPasswordFocus() {
        let app = launchLogin(
            phase: "credentials",
            path: "credentials",
            extraArguments: [
                "-reelfin-tv-login-username", "viewer",
                "-reelfin-tv-login-password", "wrong-password",
                "-reelfin-mock-auth-failure"
            ]
        )
        let username = app.textFields["tv_login_username_field"]
        let password = app.secureTextFields["tv_login_password_field"]
        let submit = app.buttons["tv_login_credentials_submit"]

        XCTAssertTrue(username.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForFocus(username))
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForFocus(password))
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForFocus(submit))

        XCUIRemote.shared.press(.select)

        XCTAssertTrue(waitForFocus(password, timeout: 5))
        XCTAssertTrue(app.otherElements["tv_login_stage_credentials"].exists)
    }

    func testQuickConnectJourneyDisplaysApprovalCodeAndCapturesFinalState() {
        let app = launchLogin(phase: "landing")
        let quickConnect = app.buttons["tv_login_quick_connect"]
        XCTAssertTrue(quickConnect.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForFocus(quickConnect))

        XCUIRemote.shared.press(.select)

        let code = app.staticTexts["tv_login_quick_connect_code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertEqual(code.label, "12  34")

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "quick-connect-approval-code"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testQuickConnectMenuReturnsToLandingOriginAndRemainsCancelled() {
        let app = launchLogin(phase: "landing")
        let quickConnect = app.buttons["tv_login_quick_connect"]
        XCTAssertTrue(quickConnect.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForFocus(quickConnect))

        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["tv_login_stage_quick_connect"].waitForExistence(timeout: 3))

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.otherElements["tv_login_stage_landing"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForFocus(quickConnect))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(waitForDisappearance(app.otherElements["tv_login_stage_quick_connect"]))
    }

    func testQuickConnectMenuReturnsToServerOriginAndRemainsCancelled() {
        let app = launchLogin(phase: "server")
        let primary = app.buttons["tv_login_server_primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 8))

        focusButton(primary, using: [.down])
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["tv_login_stage_quick_connect"].waitForExistence(timeout: 3))

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.otherElements["tv_login_stage_server"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForFocus(app.textFields["tv_login_server_field"]))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(waitForDisappearance(app.otherElements["tv_login_stage_quick_connect"]))
    }

    func testQuickConnectMenuReturnsToCredentialsOriginAndRemainsCancelled() {
        let app = launchLogin(phase: "quickConnect", path: "credentials", quickConnectOrigin: "credentials")
        XCTAssertTrue(app.otherElements["tv_login_stage_quick_connect"].waitForExistence(timeout: 8))

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.otherElements["tv_login_stage_credentials"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForFocus(app.textFields["tv_login_username_field"]))
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(waitForDisappearance(app.otherElements["tv_login_stage_quick_connect"]))
    }

    func testCompletingOnboardingHandsOffToLandingWithQuickConnectFocus() {
        let app = launchOnboarding(page: 3)
        let primaryButton = app.buttons["tv_onboarding_primary_cta"]
        XCTAssertTrue(primaryButton.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForFocus(primaryButton))

        XCUIRemote.shared.press(.select)

        XCTAssertTrue(app.otherElements["tv_login_stage_landing"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForFocus(app.buttons["tv_login_quick_connect"]))
    }

    func testMenuIsIgnoredDuringSubmittingAndSuccessAtomicPhases() {
        for phase in ["submitting", "success"] {
            let app = launchLogin(phase: phase, path: phase == "submitting" ? "credentials" : nil)
            let stage = app.otherElements["tv_login_stage_\(phase)"]
            XCTAssertTrue(stage.waitForExistence(timeout: 8))

            XCUIRemote.shared.press(.menu)

            XCTAssertEqual(app.state, .runningForeground)
            XCTAssertTrue(stage.exists)
        }
    }

    func testEveryLoginControlStaysInsideSafeRectangleAndMeetsMinimumHeight() {
        let controlsByPhase: [(String, [String], [String])] = [
            ("landing", ["tv_login_quick_connect", "tv_login_use_password", "tv_login_choose_server"], []),
            ("server", ["tv_login_server_back", "tv_login_server_primary", "tv_login_server_alternate"], ["tv_login_server_field"]),
            ("credentials", ["tv_login_credentials_back", "tv_login_credentials_submit", "tv_login_credentials_quick_connect"], ["tv_login_username_field", "tv_login_password_field"]),
            ("quickConnect", ["tv_login_quick_connect_use_password"], [])
        ]

        for (phase, buttonIdentifiers, fieldIdentifiers) in controlsByPhase {
            let app = launchLogin(phase: phase, path: phase == "credentials" ? "credentials" : nil)
            let window = app.windows.firstMatch
            XCTAssertTrue(window.waitForExistence(timeout: 8))
            let safeRectangle = window.frame.insetBy(dx: 80, dy: 60)

            for identifier in buttonIdentifiers {
                assertSafeControl(app.buttons[identifier], identifier: identifier, safeRectangle: safeRectangle)
            }

            for identifier in fieldIdentifiers {
                // XCTest exposes the editor's inner accessibility frame for tvOS
                // text fields, not the 82-point SwiftUI focus surface around it.
                assertSafePlacement(
                    app.descendants(matching: .any)[identifier],
                    identifier: identifier,
                    safeRectangle: safeRectangle
                )
            }
        }
    }

    func testServerAndCredentialsActionRowsAllocateUntruncatedLabels() {
        let actionRows: [(String, [String])] = [
            ("server", ["tv_login_server_back", "tv_login_server_primary", "tv_login_server_alternate"]),
            ("credentials", ["tv_login_credentials_back", "tv_login_credentials_submit", "tv_login_credentials_quick_connect"])
        ]

        for (phase, identifiers) in actionRows {
            let app = launchLogin(phase: phase, path: phase == "credentials" ? "credentials" : nil)

            for identifier in identifiers {
                let button = app.buttons[identifier]
                XCTAssertTrue(button.waitForExistence(timeout: 8), "Missing \(identifier).")
                XCTAssertGreaterThanOrEqual(
                    button.frame.width,
                    300,
                    "\(identifier) needs enough width for its 29-point label."
                )
            }
        }
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

    private func launchLogin(
        phase: String,
        path: String? = nil,
        quickConnectOrigin: String? = nil,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = [
            "-reelfin-mock-mode", "-reelfin-ui-logged-out",
            "-reelfin-tv-auth-screen", "login",
            "-reelfin-tv-login-phase", phase
        ]
        if let path {
            arguments += ["-reelfin-tv-login-path", path]
        }
        if let quickConnectOrigin {
            arguments += ["-reelfin-tv-login-quick-connect-origin", quickConnectOrigin]
        }
        arguments += extraArguments
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func assertSafeControl(
        _ element: XCUIElement,
        identifier: String,
        safeRectangle: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 3), "Missing \(identifier).", file: file, line: line)
        XCTAssertTrue(
            safeRectangle.contains(element.frame),
            "\(identifier) frame \(element.frame) must be inside \(safeRectangle).",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            element.frame.height,
            82,
            "\(identifier) must be at least 82 pt high.",
            file: file,
            line: line
        )
    }

    private func assertSafePlacement(
        _ element: XCUIElement,
        identifier: String,
        safeRectangle: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 3), "Missing \(identifier).", file: file, line: line)
        XCTAssertTrue(
            safeRectangle.contains(element.frame),
            "\(identifier) frame \(element.frame) must be inside \(safeRectangle).",
            file: file,
            line: line
        )
    }

    private func focusButton(_ button: XCUIElement, using directions: [XCUIRemote.Button]) {
        for direction in directions where !button.hasFocus {
            XCUIRemote.shared.press(direction)
        }
        XCTAssertTrue(waitForFocus(button), "Remote navigation did not focus \(button.identifier).")
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
