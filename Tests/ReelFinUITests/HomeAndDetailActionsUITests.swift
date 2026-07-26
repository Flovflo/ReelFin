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

        let moreButton = app.buttons["detail_more_button"].firstMatch
        XCTAssertTrue(moreButton.waitForExistence(timeout: 8))
        XCTAssertTrue(waitUntilHittable(moreButton, timeout: 5))
        capture(name: "detail-action-hierarchy")
        moreButton.tap()

        let downloadButton = app.buttons["detail_download_button"].firstMatch
        XCTAssertTrue(downloadButton.waitForExistence(timeout: 8))
        XCTAssertFalse(downloadButton.frame.isEmpty)
        downloadButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let alert = app.alerts["Downloads coming soon"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        XCTAssertTrue(
            alert.staticTexts[
                "Offline downloads are not available yet. This feature will arrive in a future update."
            ].exists
        )
    }

    func testMockDetailCarouselSelectsAdjacentNeighbor() throws {
        let app = launchMockApp()

        let continueWatchingEpisode = app.buttons[
            "media_card_button_continueWatching_cw-episode-2"
        ].firstMatch
        XCTAssertTrue(continueWatchingEpisode.waitForExistence(timeout: 12))
        XCTAssertTrue(waitUntilHittable(continueWatchingEpisode, timeout: 5))
        continueWatchingEpisode.tap()

        let carousel = app.scrollViews["detail_ios_top_carousel"].firstMatch
        XCTAssertTrue(carousel.waitForExistence(timeout: 8))
        XCTAssertTrue(detailIdentity(containing: "Continue Series", in: app).waitForExistence(timeout: 5))

        carousel.swipeLeft()

        XCTAssertTrue(detailIdentity(containing: "Resume Movie", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["detail_more_button"].exists)
        capture(name: "detail-adjacent-neighbor")
    }

    func testMockLibraryDetailEntryReturnsToLibraryRoot() throws {
        let app = launchMockApp()
        openLibrary(in: app)

        let librarySearch = app.textFields["library_search_field"].firstMatch
        XCTAssertTrue(librarySearch.waitForExistence(timeout: 8))

        let firstPoster = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "media_card_button_")
        ).firstMatch
        XCTAssertTrue(firstPoster.waitForExistence(timeout: 8))
        XCTAssertTrue(waitUntilHittable(firstPoster, timeout: 5))
        firstPoster.tap()

        let backButton = app.buttons["Back"].firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 8))
        XCTAssertTrue(app.otherElements["detail_primary_play_button"].exists)
        backButton.tap()

        XCTAssertTrue(librarySearch.waitForExistence(timeout: 8))
        XCTAssertTrue(waitUntilHittable(librarySearch, timeout: 5))
        capture(name: "library-detail-return")
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

    private func detailIdentity(containing title: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", title)
        ).firstMatch
    }

    private func capture(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
