import XCTest

final class TVAppStoreScreenshotTests: XCTestCase {
    private enum CaptureError: Error {
        case missingFocusedCard
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureFictionalStorefrontScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-reelfin-mock-mode",
            "-reelfin-screenshot-mode",
            "-reelfin-reset-screenshot-defaults",
            "-reelfin-storefront-search-query", "aurora",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        let cards = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "media_card_button_")
        )
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(app.otherElements["home_hero_artwork_ready"].waitForExistence(timeout: 20))
        try focusTopNavigation("Watch Now", in: app)
        capture(name: "01-home")

        try selectTopNavigation("Library", in: app)
        XCTAssertTrue(app.staticTexts["Library"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 15))
        capture(name: "02-library")

        let focusedCard = try focusFirstCard(in: cards)
        XCTAssertTrue(focusedCard.hasFocus)
        XCUIRemote.shared.press(.select)
        let playButton = app.buttons["detail_primary_play_button"]
        XCTAssertTrue(playButton.waitForExistence(timeout: 15))
        for _ in 0..<8 where !playButton.hasFocus {
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(playButton.hasFocus, "Expected detail Play to own focus before capture.")
        XCTAssertTrue(app.otherElements["detail_hero_artwork_ready"].waitForExistence(timeout: 20))
        capture(name: "03-detail")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 20))
        try selectTopNavigation("Search", in: app)
        XCTAssertTrue(app.staticTexts["Hollow Aurora"].waitForExistence(timeout: 15))
        capture(name: "04-search")
    }

    private func selectTopNavigation(_ label: String, in app: XCUIApplication) throws {
        try focusTopNavigation(label, in: app)
        XCUIRemote.shared.press(.select)
    }

    private func focusTopNavigation(_ label: String, in app: XCUIApplication) throws {
        let target = app.buttons[label]
        XCTAssertTrue(target.waitForExistence(timeout: 10))

        for _ in 0..<16 where !target.hasFocus {
            XCUIRemote.shared.press(.up)
        }
        let destinationLabels = ["Watch Now", "Library", "Search"]
        let destinations = destinationLabels.map { app.buttons[$0] }
        let targetIndex = destinationLabels.firstIndex(of: label)!
        for _ in 0..<4 where !target.hasFocus {
            guard let focusedIndex = destinations.firstIndex(where: \.hasFocus) else {
                XCUIRemote.shared.press(.up)
                continue
            }
            XCUIRemote.shared.press(focusedIndex < targetIndex ? .right : .left)
        }

        XCTAssertTrue(target.hasFocus, "Expected \(label) to receive top-navigation focus.")
    }

    private func focusFirstCard(in cards: XCUIElementQuery) throws -> XCUIElement {
        for _ in 0..<12 {
            let focused = cards.matching(NSPredicate(format: "hasFocus == true")).firstMatch
            if focused.exists {
                return focused
            }
            XCUIRemote.shared.press(.down)
        }

        XCTFail("Expected a fictional media card to receive focus.")
        throw CaptureError.missingFocusedCard
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

        let deviceSlug = ProcessInfo.processInfo.environment["REELFIN_SCREENSHOT_DEVICE_SLUG"] ?? "tvOS"
        let deviceDirectory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
            .appendingPathComponent(deviceSlug, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: deviceDirectory, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(
                to: deviceDirectory.appendingPathComponent("\(name).png")
            )
        } catch {
            XCTFail("Unable to export screenshot \(name): \(error.localizedDescription)", file: file, line: line)
        }
    }
}
