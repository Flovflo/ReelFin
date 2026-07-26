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

    func testMockHomeFeaturedMoreButtonOpensDetail() throws {
        let app = launchMockApp()

        let moreButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "home_featured_more_button_")
        ).firstMatch
        XCTAssertTrue(moreButton.waitForExistence(timeout: 12))
        XCTAssertTrue(waitUntilHittable(moreButton, timeout: 5))

        moreButton.tap()

        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.otherElements["detail_primary_play_button"].exists)
    }

    func testMockDetailHeroButtonsToggleWatchedAndLikedState() throws {
        let app = launchMockApp()

        let firstPoster = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "media_card_button_")
        ).firstMatch
        XCTAssertTrue(firstPoster.waitForExistence(timeout: 12))
        firstPoster.tap()

        let watchedButton = app.otherElements.matching(
            NSPredicate(format: "label == %@ AND value == %@", "Mark Watched", "not_watched")
        ).firstMatch
        XCTAssertTrue(watchedButton.waitForExistence(timeout: 8))
        XCTAssertTrue(waitUntilHittable(watchedButton, timeout: 5))

        watchedButton.tap()

        let watchedState = app.otherElements.matching(
            NSPredicate(format: "label == %@ AND value == %@", "Mark Unwatched", "watched")
        ).firstMatch
        XCTAssertTrue(watchedState.waitForExistence(timeout: 3))

        let favoriteButton = app.otherElements.matching(
            NSPredicate(format: "label == %@ AND value == %@", "Like", "not_liked")
        ).firstMatch
        XCTAssertTrue(favoriteButton.waitForExistence(timeout: 3))
        XCTAssertTrue(waitUntilHittable(favoriteButton, timeout: 5))

        favoriteButton.tap()

        let likedState = app.otherElements.matching(
            NSPredicate(format: "label == %@ AND value == %@", "Unlike", "liked")
        ).firstMatch
        XCTAssertTrue(likedState.waitForExistence(timeout: 3))
    }

    func testMockDetailDownloadButtonShowsComingSoonMessage() throws {
        let app = launchMockApp()

        let firstPoster = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "media_card_button_")
        ).firstMatch
        XCTAssertTrue(firstPoster.waitForExistence(timeout: 12))
        firstPoster.tap()

        let downloadButton = app.buttons["Download"].firstMatch
        XCTAssertTrue(downloadButton.waitForExistence(timeout: 8))
        XCTAssertTrue(waitUntilHittable(downloadButton, timeout: 5))

        downloadButton.tap()

        let alert = app.alerts["Downloads coming soon"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        XCTAssertTrue(
            alert.staticTexts[
                "Offline downloads are not available yet. This feature will arrive in a future update."
            ].exists
        )
    }

    private func launchMockApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-reelfin-mock-mode",
            "-reelfin-screenshot-mode",
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(establishHomeRoot(in: app))
        return app
    }

    private func establishHomeRoot(in app: XCUIApplication) -> Bool {
        // NavigationStack can restore one or more mock Detail destinations between isolated
        // UI-test runs. Unwind until an existing Home-only control proves the root is active.
        let homeMarker = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "home_featured_watchlist_button_")
        ).firstMatch
        let backButton = app.buttons["Back"].firstMatch
        let homeTab = app.buttons["Home"].firstMatch
        let deadline = Date().addingTimeInterval(12)

        while Date() < deadline {
            if homeMarker.exists {
                return true
            }
            if backButton.exists, backButton.isHittable {
                backButton.tap()
            } else if homeTab.exists, !homeTab.isSelected, homeTab.isHittable {
                homeTab.tap()
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return homeMarker.exists
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
}
