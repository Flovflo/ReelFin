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
        XCTAssertTrue(app.otherElements["root_sidebar"].firstMatch.exists)
        XCTAssertFalse(app.otherElements["root_tab_layout"].firstMatch.exists)

        for identifier in ["root_sidebar_home", "root_sidebar_search", "root_sidebar_settings"] {
            let destination = app.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(destination.exists)
            XCTAssertTrue(destination.isHittable)
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
