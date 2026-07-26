import XCTest

final class LibraryEditorialUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMockLibraryHeaderCompactsAndRestoresInPortrait() throws {
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchArguments += ["-reelfin-mock-mode", "-reelfin-screenshot-mode"]
        app.launch()

        addTeardownBlock {
            XCUIDevice.shared.orientation = .portrait
        }

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        openLibrary(in: app)

        let appWindow = app.windows.firstMatch
        XCTAssertTrue(appWindow.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(appWindow.frame.height, appWindow.frame.width)

        verifyHeaderJourney(in: app, screenshotPrefix: "library-portrait")
    }

    private func verifyHeaderJourney(
        in app: XCUIApplication,
        screenshotPrefix: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let search = searchField(in: app)
        let compactHeader = app.staticTexts["library_sticky_blur_header"].firstMatch

        XCTAssertTrue(search.waitForExistence(timeout: 8), file: file, line: line)
        XCTAssertTrue(waitUntilHittable(search, timeout: 5), file: file, line: line)
        XCTAssertFalse(compactHeader.isHittable, file: file, line: line)
        capture(name: "\(screenshotPrefix)-expanded")

        app.swipeUp()

        XCTAssertTrue(compactHeader.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(waitUntilHittable(compactHeader, timeout: 5), file: file, line: line)
        capture(name: "\(screenshotPrefix)-compact")

        app.swipeDown()

        XCTAssertTrue(waitUntilNotHittable(compactHeader, timeout: 5), file: file, line: line)
        XCTAssertTrue(waitUntilHittable(search, timeout: 5), file: file, line: line)
        capture(name: "\(screenshotPrefix)-restored")
    }

    private func openLibrary(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let searchTab = app.tabBars.buttons["Search"].firstMatch
        if searchTab.waitForExistence(timeout: 5) {
            searchTab.tap()
            return
        }

        if app.tabBars.buttons.count > 1 {
            app.tabBars.buttons.element(boundBy: 1).tap()
            return
        }

        let sidebarButton = app.buttons["Search"].firstMatch
        if sidebarButton.exists {
            sidebarButton.tap()
            return
        }

        XCTFail("Unable to navigate to Library", file: file, line: line)
    }

    private func searchField(in app: XCUIApplication) -> XCUIElement {
        app.textFields["library_search_field"].firstMatch
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if element.exists && element.isHittable {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return element.exists && element.isHittable
    }

    private func waitUntilNotHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if !element.isHittable {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return !element.isHittable
    }

    private func capture(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
