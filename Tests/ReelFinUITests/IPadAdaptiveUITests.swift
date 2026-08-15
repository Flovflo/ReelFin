import XCTest
import UIKit

final class IPadAdaptiveUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("Native iPad layout assertions require an iPad destination.")
        }
    }

    func testAuthenticatedMockUsesNativeSplitShell() throws {
        let app = launchStorefrontApp()
        let split = app.otherElements["root_split_layout"].firstMatch
        XCTAssertTrue(split.waitForExistence(timeout: 10))
        XCTAssertFalse(app.otherElements["root_tab_layout"].firstMatch.exists)

        let destinations: [(identifier: String, expectedScreen: XCUIElement)] = [
            ("root_sidebar_search", app.staticTexts["Library"].firstMatch),
            ("root_sidebar_settings", app.descendants(matching: .any)["settings_screen"].firstMatch),
            (
                "root_sidebar_home",
                app.buttons.matching(
                    NSPredicate(format: "identifier BEGINSWITH %@", "media_card_button_continueWatching_")
                ).firstMatch
            )
        ]

        for destination in destinations {
            let row = app.cells.containing(.any, identifier: destination.identifier).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            XCTAssertTrue(row.isHittable)
            row.tap()
            XCTAssertTrue(destination.expectedScreen.waitForExistence(timeout: 10))
        }

        let firstCard = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "media_card_button_")
        ).firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(firstCard.frame.width, 0)
        XCTAssertGreaterThan(firstCard.frame.height, 0)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(firstCard.frame))
    }

    func testLoggedOutMockControlsRemainHittableAcrossRotation() throws {
        let app = launchStorefrontApp(extraArguments: ["-reelfin-ui-logged-out", "-reelfin-force-onboarding"])
        let primary = app.buttons["onboarding_primary_cta"].firstMatch
        XCTAssertTrue(primary.waitForExistence(timeout: 10))
        XCTAssertTrue(primary.isHittable)

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        XCTAssertTrue(primary.isHittable)

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        XCTAssertTrue(primary.isHittable)
    }

    private func launchStorefrontApp(extraArguments: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += [
            "-reelfin-mock-mode",
            "-reelfin-screenshot-mode",
            "-reelfin-reset-screenshot-defaults",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark"
        ]
        app.launchArguments += extraArguments
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        return app
    }
}
