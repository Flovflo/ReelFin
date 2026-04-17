import XCTest

final class HomeAndDetailActionsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMockHomeFeaturedWatchlistButtonTogglesState() throws {
        let app = launchMockApp()

        let watchlistButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "home_featured_watchlist_button_")
        ).firstMatch
        XCTAssertTrue(watchlistButton.waitForExistence(timeout: 12))
        XCTAssertTrue(waitUntilHittable(watchlistButton, timeout: 5))
        XCTAssertEqual(watchlistButton.value as? String, "not_liked")

        watchlistButton.tap()

        XCTAssertTrue(waitForValue("liked", on: watchlistButton, timeout: 3))
        XCTAssertEqual(watchlistButton.label, "Unlike")
    }

    func testMockDetailHeroButtonsToggleWatchedAndLikedState() throws {
        let app = launchMockApp()

        let firstPoster = app.buttons["media_card_button_continueWatching_cw-movie-1"].firstMatch
        XCTAssertTrue(firstPoster.waitForExistence(timeout: 12))
        firstPoster.tap()

        let watchedButton = findFirstExistingElement(
            [
                app.buttons["detail_watched_button"].firstMatch,
                app.buttons.matching(NSPredicate(format: "label == %@", "Mark Watched")).firstMatch,
                app.buttons.matching(NSPredicate(format: "label == %@", "Mark Unwatched")).firstMatch
            ],
            timeout: 8
        )
        XCTAssertNotNil(watchedButton)
        guard let watchedButton else { return }
        XCTAssertTrue(waitUntilHittable(watchedButton, timeout: 5))
        XCTAssertEqual(watchedButton.label, "Mark Watched")

        watchedButton.tap()

        XCTAssertTrue(waitForLabel("Mark Unwatched", on: watchedButton, timeout: 3))
        XCTAssertEqual(watchedButton.label, "Mark Unwatched")

        let favoriteButton = findFirstExistingElement(
            [
                app.buttons["detail_favorite_button"].firstMatch,
                app.buttons.matching(NSPredicate(format: "label == %@", "Like")).firstMatch,
                app.buttons.matching(NSPredicate(format: "label == %@", "Unlike")).firstMatch
            ],
            timeout: 3
        )
        XCTAssertNotNil(favoriteButton)
        guard let favoriteButton else { return }
        XCTAssertTrue(waitUntilHittable(favoriteButton, timeout: 5))
        XCTAssertEqual(favoriteButton.label, "Like")

        favoriteButton.tap()

        XCTAssertTrue(waitForLabel("Unlike", on: favoriteButton, timeout: 3))
        XCTAssertEqual(favoriteButton.label, "Unlike")
    }

    private func launchMockApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-reelfin-mock-mode", "-reelfin-screenshot-mode"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        return app
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

    private func waitForValue(_ expectedValue: String, on element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if (element.value as? String) == expectedValue {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return (element.value as? String) == expectedValue
    }

    private func waitForLabel(_ expectedLabel: String, on element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if element.label == expectedLabel {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return element.label == expectedLabel
    }

    private func findFirstExistingElement(_ elements: [XCUIElement], timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let element = elements.first(where: \.exists) {
                return element
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return elements.first(where: \.exists)
    }
}
