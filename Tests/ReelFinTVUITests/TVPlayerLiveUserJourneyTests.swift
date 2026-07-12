import XCTest

/// Opt-in only. The test process receives no Jellyfin URL, credentials, token, user ID or item ID.
/// The already-authenticated DEBUG tvOS app resolves the redacted alias itself.
final class TVPlayerLiveUserJourneyTests: XCTestCase {
    private enum JourneyError: Error { case invalidPlaybackTime }
    private enum ResumeChoice: Equatable { case continueDefault, restart }

    private var requestedLoopCount = 10
    private var didCaptureCompactLaunchStates = false
    private var didCaptureCompactBuffering = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        let config = liveConfiguration()
        guard config["REELFIN_LIVE_UI_FIXTURE_ALIAS"] == "star-city-s1e1" else {
            throw XCTSkip("Live Jellyfin tvOS journeys are opt-in; provide only alias star-city-s1e1 in .artifacts/player-e2e/tvos-live-ui.env.")
        }
        requestedLoopCount = Int(config["REELFIN_TV_UI_LOOP_COUNT"] ?? "10") ?? 10
    }

    func testContinuePauseResumeSeekToZeroAndForward() throws {
        let app = try launchStarCityDetail()
        try startPlayback(in: app, choice: .continueDefault)
        try requireHealthyPlayback(in: app)
        try assertInitialPosition(.continueDefault, in: app)
        assertCircularInputUnavailable(in: app)

        let beforePause = try playbackTime(in: app)
        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(waitForTransport("paused", in: app, timeout: 8))
        XCTAssertFalse(app.otherElements["player_playback_advancing"].waitForExistence(timeout: 3))
        let paused = try playbackTime(in: app)
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        XCTAssertEqual(try playbackTime(in: app), paused, accuracy: 0.35)

        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(waitForTransport("playing", in: app, timeout: 12))
        XCTAssertTrue(waitForPlaybackTime(greaterThan: max(beforePause, paused) + 0.5, in: app, timeout: 15))

        let current = try playbackTime(in: app)
        for _ in 0..<max(1, Int(ceil(current / 10))) { XCUIRemote.shared.press(.left) }
        XCTAssertTrue(app.otherElements["player_seek_target_zero"].waitForExistence(timeout: 20))
        XCTAssertLessThanOrEqual(try playbackTime(in: app), 15)
        XCTAssertTrue(app.otherElements["player_playback_advancing"].waitForExistence(timeout: 20))

        XCUIRemote.shared.press(.right)
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(app.otherElements["player_seek_completed"].waitForExistence(timeout: 15))
        XCTAssertTrue(waitForPlaybackTime(greaterThan: 20, in: app, timeout: 20))
        XCTAssertFalse(app.otherElements["player_error"].exists)
        attachScreenshot(app, name: "continue-pause-seek-complete")
    }

    func testAudioSubtitlesVideoInfoDetailsAndPausedContinue() throws {
        let app = try launchStarCityDetail()
        try startPlayback(in: app, choice: .continueDefault)
        try requireHealthyPlayback(in: app)
        revealChrome(in: app)

        try changeSubtitleLanguageAndStyle(in: app)
        try changeAudioAndRevalidate(in: app, navigation: [.right])

        focusButton("native_player_video_button", in: app, using: [.right])
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["native_player_video_panel"].waitForExistence(timeout: 8))

        XCTAssertTrue(app.otherElements["player_audio_rendering_ready"].waitForExistence(timeout: 20))
        let audioRoute = app.otherElements["player_audio_rendering_ready"].value as? String
        XCTAssertTrue([
            "custom_avfoundation_selected_audible_advancing",
            "native_sample_buffer_audio_renderer_accepted"
        ].contains(audioRoute ?? ""))

        XCTAssertTrue(app.staticTexts["Vidéo"].exists)
        XCUIRemote.shared.press(.menu)
        let chromeFocusMarker = app.otherElements["native_player_chrome_focused_control"]
        XCTAssertTrue(chromeFocusMarker.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForValue("native_player_video_button", on: chromeFocusMarker, timeout: 5),
            "Closing the video panel must restore the chrome focus state to Video; observed \(String(describing: chromeFocusMarker.value))."
        )
        XCTAssertTrue(
            waitForFocus(app.buttons["native_player_video_button"], timeout: 5),
            "Closing the video panel must restore focus to its originating control."
        )

        XCUIRemote.shared.press(.down)
        XCTAssertTrue(
            waitForFocus(app.buttons["native_player_timeline_scrubber"], timeout: 5),
            "Down from Video must focus the playback timeline."
        )
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(
            waitForFocus(app.buttons["native_player_info_button"], timeout: 5),
            "Down from the timeline must focus Info."
        )
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["native_player_info_panel"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Info"].exists)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(
            waitForFocus(app.buttons["native_player_info_button"], timeout: 5),
            "Closing Info must restore focus to its originating control."
        )

        focusButton("native_player_insight_button", in: app, using: [.right])
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["native_player_insight_panel"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Détails"].exists)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(
            waitForFocus(app.buttons["native_player_insight_button"], timeout: 5),
            "Closing Details must restore focus to its originating control."
        )

        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(waitForTransport("paused", in: app, timeout: 8))
        focusButton("native_player_continue_watching_button", in: app, using: [.right])
        XCUIRemote.shared.press(.select)
        XCTAssertFalse(app.otherElements["native_player_chrome"].waitForExistence(timeout: 2))
        XCTAssertTrue(waitForTransport("playing", in: app, timeout: 8))

        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["native_player_chrome"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.otherElements["detail_screen"].waitForExistence(timeout: 12))
    }

    func testRepeatedContinueAndRestartJourneysRemainHealthy() throws {
        let loopCount = max(10, requestedLoopCount)
        let app = try launchStarCityDetail()

        for iteration in 0..<loopCount {
            let choice: ResumeChoice = iteration.isMultiple(of: 2) ? .continueDefault : .restart
            try startPlayback(in: app, choice: choice)
            try requireHealthyPlayback(in: app)
            try assertInitialPosition(choice, in: app)
            XCUIRemote.shared.press(.right)
            XCTAssertTrue(app.otherElements["player_seek_completed"].waitForExistence(timeout: 15))
            XCTAssertFalse(app.otherElements["player_error"].exists)
            dismissPlayerToDetail(in: app)
            XCTAssertTrue(app.otherElements["detail_screen"].waitForExistence(timeout: 12))
        }
    }

    func testHomeAndLibraryFocusSurfacesRemainStableAcrossRemoteMoves() throws {
        let app = launchAuthenticatedRoot()
        let homeCards = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "media_card_button_")
        )
        let landscapeCards = homeCards.matching(
            NSPredicate(format: "identifier CONTAINS[c] %@", "continueWatching")
        )
        XCTAssertTrue(landscapeCards.firstMatch.waitForExistence(timeout: 20))

        let landscape = try focusFirstCard(in: landscapeCards, app: app, using: .down, maximumMoves: 12)
        assertUnclipped(landscape, in: app)
        attachScreenshot(app, name: "home-landscape-focus")

        let poster = try moveToDistinctFocusedCard(
            from: landscape,
            in: homeCards,
            app: app,
            using: .down,
            maximumMoves: 4,
            excludingIdentifierFragment: "continueWatching"
        )
        assertUnclipped(poster, in: app)
        attachScreenshot(app, name: "home-poster-focus")

        try openLibrary(in: app)
        let libraryCards = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "media_card_button_")
        )
        var left = try focusFirstCard(in: libraryCards, app: app, using: .down, maximumMoves: 12)
        for _ in 0..<8 where left.frame.midX > 400 {
            left = try moveToDistinctFocusedCard(
                from: left,
                in: libraryCards,
                app: app,
                using: .left,
                maximumMoves: 1
            )
        }
        XCTAssertLessThanOrEqual(left.frame.midX, 400)
        assertUnclipped(left, in: app)
        attachScreenshot(app, name: "library-first-row-left")

        var middle = left
        for _ in 0..<8 where middle.frame.midX < 850 {
            middle = try moveToDistinctFocusedCard(
                from: middle,
                in: libraryCards,
                app: app,
                using: .right,
                maximumMoves: 1
            )
        }
        XCTAssertTrue((850...1_300).contains(middle.frame.midX))
        assertSameRow(left, middle)
        assertUnclipped(middle, in: app)
        attachScreenshot(app, name: "library-first-row-middle")

        var right = middle
        for _ in 0..<8 where right.frame.midX < 1_600 {
            right = try moveToDistinctFocusedCard(
                from: right,
                in: libraryCards,
                app: app,
                using: .right,
                maximumMoves: 1
            )
        }
        XCTAssertGreaterThanOrEqual(right.frame.midX, 1_600)
        assertSameRow(middle, right)
        assertUnclipped(right, in: app)
        attachScreenshot(app, name: "library-first-row-right")
    }

    func testCompactResumeChoiceMetricsFocusAndCancelRemainPlayerFree() throws {
        let app = try launchStarCityDetail()
        let episodeOne = app.buttons["detail_episode_1_1"]
        XCTAssertTrue(episodeOne.waitForExistence(timeout: 20))
        for _ in 0..<4 where !episodeOne.hasFocus { XCUIRemote.shared.press(.down) }
        XCTAssertTrue(episodeOne.hasFocus)
        XCUIRemote.shared.press(.select)

        let choiceMarker = app.otherElements["playback_resume_choice"]
        let continueMarker = app.otherElements["playback_resume_choice_continue"]
        let restartMarker = app.otherElements["playback_resume_choice_restart"]
        XCTAssertTrue(choiceMarker.waitForExistence(timeout: 8))
        XCTAssertTrue(continueMarker.waitForExistence(timeout: 5))
        XCTAssertTrue(restartMarker.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue("resume_focused", on: choiceMarker, timeout: 5))
        XCTAssertTrue(waitForValue("focused", on: continueMarker, timeout: 5))

        let continueButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Continuer à")
        ).firstMatch
        let restartButton = app.buttons["Recommencer"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        XCTAssertTrue(restartButton.waitForExistence(timeout: 5))
        let focusedContinueFrame = continueButton.frame
        let restingRestartFrame = restartButton.frame
        XCTAssertEqual(focusedContinueFrame.height / restingRestartFrame.height, 1.025, accuracy: 0.01)
        XCTAssertEqual(focusedContinueFrame.width / restingRestartFrame.width, 1.025, accuracy: 0.01)
        XCTAssertLessThanOrEqual(continueButton.frame.union(restartButton.frame).width, 760)
        attachScreenshot(app, name: "compact-resume-choice-cancel")

        XCUIRemote.shared.press(.right)
        XCTAssertTrue(waitForValue("restart_focused", on: choiceMarker, timeout: 5))
        XCTAssertTrue(waitForValue("focused", on: restartMarker, timeout: 5))
        XCTAssertTrue(waitForValue("not_focused", on: continueMarker, timeout: 5))
        let restingContinueFrame = continueButton.frame
        let focusedRestartFrame = restartButton.frame
        XCTAssertEqual(restingContinueFrame.size.width, restingRestartFrame.size.width, accuracy: 2)
        XCTAssertEqual(restingContinueFrame.size.height, restingRestartFrame.size.height, accuracy: 2)
        XCTAssertEqual(focusedRestartFrame.size.width, focusedContinueFrame.size.width, accuracy: 2)
        XCTAssertEqual(focusedRestartFrame.size.height, focusedContinueFrame.size.height, accuracy: 2)
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(waitForValue("resume_focused", on: choiceMarker, timeout: 5))

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForDisappearance(choiceMarker, timeout: 5))
        XCTAssertTrue(app.otherElements["detail_screen"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["native_player_screen"].exists)
        XCTAssertFalse(app.otherElements["custom_player_launch_preparation"].exists)
    }

    func testHomeCardBackRestoresExactFocusAndKeepsAppForeground() throws {
        let app = launchAuthenticatedRoot()
        let sourceCard = try focusFirstMediaCard(in: app)
        let sourceIdentifier = sourceCard.identifier

        XCUIRemote.shared.press(.select)
        attachScreenshot(app, name: "home-detail-opening")
        let primaryPlay = app.buttons["detail_primary_play_button"]
        XCTAssertTrue(primaryPlay.waitForExistence(timeout: 15))
        attachScreenshot(app, name: "home-detail-presented")
        XCUIRemote.shared.press(.menu)
        attachScreenshot(app, name: "home-detail-closing")

        XCTAssertTrue(waitForDisappearance(primaryPlay, timeout: 8))
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(
            waitForFocus(app.buttons[sourceIdentifier], timeout: 8),
            "Back from Detail must restore the exact Home card \(sourceIdentifier)."
        )
    }

    func testLibraryPosterBackRestoresExactFocusAndKeepsAppForeground() throws {
        let app = launchAuthenticatedRoot()
        try openLibrary(in: app)
        let sourcePoster = try focusFirstMediaCard(in: app)
        let sourceIdentifier = sourcePoster.identifier

        XCUIRemote.shared.press(.select)
        attachScreenshot(app, name: "library-detail-opening")
        let primaryPlay = app.buttons["detail_primary_play_button"]
        XCTAssertTrue(primaryPlay.waitForExistence(timeout: 15))
        attachScreenshot(app, name: "library-detail-presented")
        XCUIRemote.shared.press(.menu)
        attachScreenshot(app, name: "library-detail-closing")

        XCTAssertTrue(waitForDisappearance(primaryPlay, timeout: 8))
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(
            waitForFocus(app.buttons[sourceIdentifier], timeout: 8),
            "Back from Detail must restore the exact Library poster \(sourceIdentifier)."
        )
    }

    func testRapidDetailBackPressesRemainInsideApp() throws {
        let app = launchAuthenticatedRoot()
        let sourceCard = try focusFirstMediaCard(in: app)
        let sourceIdentifier = sourceCard.identifier

        XCUIRemote.shared.press(.select)
        let primaryPlay = app.buttons["detail_primary_play_button"]
        XCTAssertTrue(primaryPlay.waitForExistence(timeout: 15))
        XCUIRemote.shared.press(.menu)
        XCUIRemote.shared.press(.menu)

        XCTAssertTrue(waitForDisappearance(primaryPlay, timeout: 8))
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(
            waitForFocus(app.buttons[sourceIdentifier], timeout: 8),
            "A repeated Back during close must be consumed without leaving ReelFin."
        )
    }

    private func launchAuthenticatedRoot() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["REELFIN_TV_UI_AUTOMATION"] = "0"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        return app
    }

    private func openLibrary(in app: XCUIApplication) throws {
        let library = app.buttons["Library"]
        let watchNow = app.buttons["Watch Now"]
        let search = app.buttons["Search"]
        XCTAssertTrue(library.waitForExistence(timeout: 15))

        for _ in 0..<16 where !watchNow.hasFocus && !search.hasFocus && !library.hasFocus {
            XCUIRemote.shared.press(.up)
        }
        XCTAssertTrue(
            watchNow.hasFocus || search.hasFocus || library.hasFocus,
            "Up navigation must reach the top navigation before selecting Library."
        )
        for _ in 0..<3 where !library.hasFocus {
            XCUIRemote.shared.press(.right)
        }
        XCTAssertTrue(library.hasFocus, "Remote navigation must focus the Library destination.")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Library"].waitForExistence(timeout: 15))
    }

    private func focusFirstMediaCard(in app: XCUIApplication) throws -> XCUIElement {
        let mediaCards = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "media_card_button_")
        )
        XCTAssertTrue(mediaCards.firstMatch.waitForExistence(timeout: 20))

        for _ in 0..<12 {
            if let focused = mediaCards.allElementsBoundByIndex.first(where: \.hasFocus),
               waitForStableFocus(focused, in: mediaCards) {
                return focused
            }
            XCUIRemote.shared.press(.down)
        }

        throw XCTSkip("The authenticated live library did not expose a focusable media card.")
    }

    private func waitForStableFocus(_ expected: XCUIElement, in query: XCUIElementQuery) -> Bool {
        var matchingObservations = 0
        let deadline = Date().addingTimeInterval(3)

        while Date() < deadline {
            let focused = query.allElementsBoundByIndex.filter(\.hasFocus)
            XCTAssertLessThanOrEqual(focused.count, 1, "Focus must never be ambiguous across media cards.")
            if focused.first?.identifier == expected.identifier {
                matchingObservations += 1
                if matchingObservations == 3 { return true }
            } else {
                matchingObservations = 0
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.12))
        }

        return false
    }

    private func focusFirstCard(
        in query: XCUIElementQuery,
        app: XCUIApplication,
        using direction: XCUIRemote.Button,
        maximumMoves: Int
    ) throws -> XCUIElement {
        for _ in 0...maximumMoves {
            if let focused = try uniqueFocusedCard(in: query) { return focused }
            XCUIRemote.shared.press(direction)
        }
        throw XCTSkip("The authenticated surface did not expose the required focusable card.")
    }

    private func moveToDistinctFocusedCard(
        from source: XCUIElement,
        in query: XCUIElementQuery,
        app: XCUIApplication,
        using direction: XCUIRemote.Button,
        maximumMoves: Int,
        excludingIdentifierFragment: String? = nil
    ) throws -> XCUIElement {
        let sourceIdentifier = source.identifier
        for _ in 0..<maximumMoves {
            XCUIRemote.shared.press(direction)
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                if let focused = try uniqueFocusedCard(in: query),
                   focused.identifier != sourceIdentifier,
                   excludingIdentifierFragment.map({ !focused.identifier.localizedCaseInsensitiveContains($0) }) ?? true {
                    assertFocusRemainsStable(focused, in: query)
                    return focused
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
        }
        XCTFail("One remote \(direction) move must yield exactly one distinct, stable focused card.")
        throw JourneyError.invalidPlaybackTime
    }

    private func uniqueFocusedCard(in query: XCUIElementQuery) throws -> XCUIElement? {
        let focused = query.allElementsBoundByIndex.filter(\.hasFocus)
        XCTAssertLessThanOrEqual(focused.count, 1, "Focus must never be ambiguous across media cards.")
        return focused.first
    }

    private func assertFocusRemainsStable(_ expected: XCUIElement, in query: XCUIElementQuery) {
        for _ in 0..<3 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.12))
            let focused = query.allElementsBoundByIndex.filter(\.hasFocus)
            XCTAssertEqual(focused.count, 1, "A remote move must produce one focused accessibility value.")
            XCTAssertEqual(focused.first?.identifier, expected.identifier, "Focus changed more than once for one remote move.")
        }
    }

    private func assertSameRow(_ leading: XCUIElement, _ trailing: XCUIElement) {
        XCTAssertEqual(trailing.frame.midY, leading.frame.midY, accuracy: 8)
    }

    private func assertUnclipped(_ element: XCUIElement, in app: XCUIApplication) {
        let viewport = app.windows.firstMatch.frame
        XCTAssertFalse(element.frame.isEmpty)
        XCTAssertTrue(viewport.contains(element.frame), "Focused card \(element.identifier) must remain inside the visible viewport.")
    }

    private func launchStarCityDetail() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["REELFIN_TV_UI_AUTOMATION"] = "1"
        app.launchEnvironment["REELFIN_LIVE_UI_FIXTURE_ALIAS"] = "star-city-s1e1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        XCTAssertTrue(app.otherElements["detail_screen"].waitForExistence(timeout: 45))
        let primaryPlay = app.buttons["detail_primary_play_button"]
        XCTAssertTrue(primaryPlay.waitForExistence(timeout: 12))
        for _ in 0..<3 where !primaryPlay.hasFocus { XCUIRemote.shared.press(.down) }
        XCTAssertTrue(primaryPlay.hasFocus)
        return app
    }

    private func startPlayback(in app: XCUIApplication, choice: ResumeChoice) throws {
        let shouldCaptureCompactLaunchStates = !didCaptureCompactLaunchStates
        let episodeOne = app.buttons["detail_episode_1_1"]
        XCTAssertTrue(episodeOne.waitForExistence(timeout: 20))
        for _ in 0..<4 where !episodeOne.hasFocus { XCUIRemote.shared.press(.down) }
        XCTAssertTrue(episodeOne.hasFocus)
        XCUIRemote.shared.press(.select)

        let choiceMarker = app.otherElements["playback_resume_choice"]
        XCTAssertTrue(choiceMarker.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForValue("resume_focused", on: choiceMarker, timeout: 5))
        if choice == .restart {
            XCUIRemote.shared.press(.right)
            XCTAssertTrue(waitForValue("restart_focused", on: choiceMarker, timeout: 5))
        }
        if shouldCaptureCompactLaunchStates {
            attachScreenshot(app, name: "compact-resume-choice")
        }
        XCUIRemote.shared.press(.select)
        if shouldCaptureCompactLaunchStates {
            let preparationScreenshot = app.screenshot()
            let preparationPanel = app.otherElements["custom_player_launch_preparation"]
            XCTAssertTrue(
                preparationPanel.exists || preparationPanel.waitForExistence(timeout: 8),
                "The compact player preparation panel must appear before the first rendered frame."
            )
            attachScreenshot(preparationScreenshot, name: "compact-player-preparation")
            didCaptureCompactLaunchStates = true
        }
        XCTAssertTrue(app.otherElements["native_player_screen"].waitForExistence(timeout: 12))
    }

    private func requireHealthyPlayback(in app: XCUIApplication) throws {
        captureCompactBufferingIfVisible(in: app)
        XCTAssertTrue(app.otherElements["player_video_rendering_ready"].waitForExistence(timeout: 35))
        captureCompactBufferingIfVisible(in: app)
        XCTAssertTrue(app.otherElements["player_audio_rendering_ready"].waitForExistence(timeout: 35))
        XCTAssertTrue(app.otherElements["player_playback_advancing"].waitForExistence(timeout: 35))
        XCTAssertFalse(app.otherElements["player_error"].exists)
        let generation = app.otherElements["native_player_reader_generation"].firstMatch
        if generation.exists { XCTAssertNotNil(Int(generation.value as? String ?? "")) }
    }

    private func assertCircularInputUnavailable(in app: XCUIApplication) {
        revealChrome(in: app)
        let circularAvailability = app.otherElements["native_player_circular_scrub_available"]
        XCTAssertTrue(circularAvailability.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForValue("false", on: circularAvailability, timeout: 5),
            "Device Hub exposes cardinal Remote controls but no indirect clickpad coordinates; availability must stay false."
        )
        XCTAssertTrue(waitForValue("idle", on: app.otherElements["native_player_circular_scrub_state"], timeout: 5))
        XCTAssertTrue(waitForValue("none", on: app.otherElements["native_player_circular_scrub_preview_bucket"], timeout: 5))

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForDisappearance(app.otherElements["native_player_chrome"], timeout: 5))
        XCTAssertTrue(app.otherElements["native_player_screen"].exists)
    }

    private func captureCompactBufferingIfVisible(in app: XCUIApplication) {
        guard !didCaptureCompactBuffering else { return }
        let bufferingPanel = app.otherElements["custom_player_buffering"]
        guard bufferingPanel.exists else { return }
        attachScreenshot(app, name: "compact-player-buffering")
        didCaptureCompactBuffering = true
    }

    private func assertInitialPosition(_ choice: ResumeChoice, in app: XCUIApplication) throws {
        let actual = try playbackTime(in: app)
        switch choice {
        case .continueDefault:
            XCTAssertTrue((425...470).contains(actual), "Continue must start from the actual saved seven-minute position, got \(actual).")
        case .restart:
            XCTAssertLessThanOrEqual(actual, 15, "Restart must begin at the actual start, got \(actual).")
        }
    }

    private func changeSubtitleLanguageAndStyle(in app: XCUIApplication) throws {
        let buttonID = "native_player_subtitles_button"
        let menu = app.otherElements["native_player_subtitles_menu"]
        let rootMarker = app.otherElements["native_player_avkit_subtitles_root"]
        let languagesMarker = app.otherElements["native_player_avkit_subtitle_languages"]
        let stylesMarker = app.otherElements["native_player_avkit_subtitle_styles"]
        let focusMarker = app.otherElements["native_player_track_focused_title"]
        let pageMarker = app.otherElements["native_player_track_menu_page"]

        focusButton(buttonID, in: app, using: [.up])
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(menu.waitForExistence(timeout: 8))
        XCTAssertTrue(rootMarker.waitForExistence(timeout: 8))
        XCTAssertTrue(focusMarker.waitForExistence(timeout: 5))
        XCTAssertTrue(pageMarker.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue("subtitles_root", on: pageMarker, timeout: 5))
        XCTAssertTrue(waitForAnyValue(["On", "Off"], on: focusMarker, timeout: 5))
        XCTAssertTrue(app.staticTexts["Transparent Background"].exists)
        attachScreenshot(app, name: "avkit-subtitles-root")

        let initialRootFocus = focusMarker.value as? String ?? ""
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(
            waitForDifferentValue(from: initialRootFocus, on: focusMarker, timeout: 5),
            "Down must move focus to another Subtitles root row."
        )
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(
            waitForValue(initialRootFocus, on: focusMarker, timeout: 5),
            "Up must return to \(initialRootFocus); observed \(String(describing: focusMarker.value))."
        )

        focusMenuRow("Language", in: app, using: .down, maximumMoves: 3)
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(
            waitForValue("subtitle_languages", on: pageMarker, timeout: 5),
            "Right on Language must open the language submenu exactly once; page is \(String(describing: pageMarker.value)), focus is \(String(describing: focusMarker.value))."
        )
        XCTAssertTrue(languagesMarker.waitForExistence(timeout: 8))
        XCTAssertGreaterThanOrEqual(menuChoiceButtons(in: app).count, 2)
        XCTAssertEqual(menuChoiceButtons(in: app).matching(selectedPredicate).count, 1)
        XCTAssertTrue(
            waitForDifferentValue(from: "Language", on: focusMarker, timeout: 5),
            "The Language submenu must establish focus before handling Left."
        )
        attachScreenshot(app, name: "avkit-language")

        XCUIRemote.shared.press(.left)
        XCTAssertTrue(menu.exists)
        XCTAssertTrue(waitForValue("subtitles_root", on: pageMarker, timeout: 5))
        XCTAssertTrue(waitForValue("Language", on: focusMarker, timeout: 5))

        XCUIRemote.shared.press(.right)
        XCTAssertTrue(waitForValue("subtitle_languages", on: pageMarker, timeout: 5))
        let beforeLanguageSelection = try playbackTime(in: app)
        let originalLanguage = try changeFocusedChoiceAndSelect(in: app)
        XCTAssertTrue(menu.exists, "Selecting a subtitle language must return to the Subtitles root.")
        XCTAssertTrue(waitForValue("subtitles_root", on: pageMarker, timeout: 5))
        XCTAssertTrue(waitForValue("Language", on: focusMarker, timeout: 5))
        try assertPlaybackContinues(afterStartingAt: beforeLanguageSelection, in: app)

        XCUIRemote.shared.press(.right)
        XCTAssertTrue(waitForValue("subtitle_languages", on: pageMarker, timeout: 5))
        let changedLanguage = selectedChoice(in: app)
        XCTAssertTrue(changedLanguage.exists)
        XCTAssertNotEqual(changedLanguage.label, originalLanguage)
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(waitForValue("Language", on: focusMarker, timeout: 5))

        focusMenuRow("Style", in: app, using: .down, maximumMoves: 1)
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(
            waitForValue("subtitle_styles", on: pageMarker, timeout: 5),
            "Right on Style must open the style submenu exactly once; page is \(String(describing: pageMarker.value)), focus is \(String(describing: focusMarker.value))."
        )
        XCTAssertTrue(stylesMarker.waitForExistence(timeout: 8))
        XCTAssertTrue(
            waitForDifferentValue(from: "Style", on: focusMarker, timeout: 5),
            "The Style submenu must establish focus before handling Menu."
        )
        XCTAssertTrue(app.staticTexts["Transparent Background"].exists)
        XCTAssertTrue(app.staticTexts["Subtle Background"].exists)
        attachScreenshot(app, name: "avkit-style")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(menu.exists, "Menu in the Style submenu must return to Subtitles root.")
        XCTAssertTrue(waitForValue("subtitles_root", on: pageMarker, timeout: 5))
        XCTAssertTrue(waitForValue("Style", on: focusMarker, timeout: 5))

        XCUIRemote.shared.press(.right)
        XCTAssertTrue(waitForValue("subtitle_styles", on: pageMarker, timeout: 5))
        let beforeFirstStyleSelection = try playbackTime(in: app)
        let firstOriginalStyle = try changeFocusedChoiceAndSelect(in: app)
        XCTAssertTrue(menu.exists, "Selecting a subtitle style must return to the Subtitles root.")
        XCTAssertTrue(waitForValue("subtitles_root", on: pageMarker, timeout: 5))
        XCTAssertTrue(waitForValue("Style", on: focusMarker, timeout: 5))
        try assertPlaybackContinues(afterStartingAt: beforeFirstStyleSelection, in: app)

        XCUIRemote.shared.press(.right)
        XCTAssertTrue(waitForValue("subtitle_styles", on: pageMarker, timeout: 5))
        XCTAssertTrue(stylesMarker.waitForExistence(timeout: 8))
        XCTAssertTrue(
            waitForAnyValue(
                ["Transparent Background", "Subtle Background"],
                on: focusMarker,
                timeout: 5
            )
        )
        XCTAssertEqual(menuChoiceButtons(in: app).matching(selectedPredicate).count, 1)
        let firstSelectedStyle = selectedChoice(in: app)
        XCTAssertTrue(firstSelectedStyle.exists)
        let firstSelectedStyleLabel = firstSelectedStyle.label
        XCTAssertNotEqual(firstSelectedStyleLabel, firstOriginalStyle)

        let beforeSecondStyleSelection = try playbackTime(in: app)
        let secondOriginalStyle = try changeFocusedChoiceAndSelect(in: app)
        XCTAssertTrue(menu.exists, "Selecting the second subtitle style must return to the Subtitles root.")
        XCTAssertTrue(waitForValue("subtitles_root", on: pageMarker, timeout: 5))
        XCTAssertTrue(waitForValue("Style", on: focusMarker, timeout: 5))
        try assertPlaybackContinues(afterStartingAt: beforeSecondStyleSelection, in: app)

        XCUIRemote.shared.press(.right)
        XCTAssertTrue(waitForValue("subtitle_styles", on: pageMarker, timeout: 5))
        XCTAssertTrue(stylesMarker.waitForExistence(timeout: 8))
        XCTAssertTrue(
            waitForAnyValue(
                ["Transparent Background", "Subtle Background"],
                on: focusMarker,
                timeout: 5
            )
        )
        XCTAssertEqual(menuChoiceButtons(in: app).matching(selectedPredicate).count, 1)
        let secondSelectedStyle = selectedChoice(in: app)
        XCTAssertTrue(secondSelectedStyle.exists)
        let secondSelectedStyleLabel = secondSelectedStyle.label
        XCTAssertNotEqual(secondSelectedStyleLabel, secondOriginalStyle)
        XCTAssertNotEqual(firstSelectedStyleLabel, secondSelectedStyleLabel)
        XCTAssertEqual(
            Set([firstSelectedStyleLabel, secondSelectedStyleLabel]),
            Set(["Transparent Background", "Subtle Background"])
        )

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForValue("subtitles_root", on: pageMarker, timeout: 5))
        XCTAssertTrue(waitForValue("Style", on: focusMarker, timeout: 5))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForDisappearance(menu, timeout: 8))
        XCTAssertTrue(waitForFocus(app.buttons[buttonID], timeout: 5))
    }

    private func changeAudioAndRevalidate(
        in app: XCUIApplication,
        navigation: [XCUIRemote.Button]
    ) throws {
        let buttonID = "native_player_audio_button"
        let menu = app.otherElements["native_player_audio_menu"]
        let audioMarker = app.otherElements["native_player_avkit_audio_menu"]

        focusButton(buttonID, in: app, using: navigation)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(menu.waitForExistence(timeout: 8))
        XCTAssertTrue(audioMarker.waitForExistence(timeout: 8))
        attachScreenshot(app, name: "avkit-audio")
        let beforeAudioSelection = try playbackTime(in: app)
        let originalLabel = try changeFocusedChoiceAndSelect(in: app)
        XCTAssertTrue(waitForDisappearance(menu, timeout: 8), "Audio selection may close its root card.")
        try assertPlaybackContinues(afterStartingAt: beforeAudioSelection, in: app)

        revealChromeAfterAutoHide(in: app)
        focusButton(buttonID, in: app, using: navigation)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(menu.waitForExistence(timeout: 8))
        let changed = selectedChoice(in: app)
        XCTAssertTrue(changed.exists)
        XCTAssertNotEqual(changed.label, originalLabel)
        XCTAssertEqual(menuChoiceButtons(in: app).matching(selectedPredicate).count, 1)
        let focusMarker = app.otherElements["native_player_track_focused_title"]
        XCTAssertTrue(waitForValue(changed.label, on: focusMarker, timeout: 5))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForDisappearance(menu, timeout: 8))
        XCTAssertTrue(waitForFocus(app.buttons[buttonID], timeout: 5))
    }

    private func assertPlaybackContinues(
        afterStartingAt baseline: Double,
        in app: XCUIApplication
    ) throws {
        XCTAssertTrue(waitForTransport("playing", in: app, timeout: 12))
        XCTAssertTrue(app.otherElements["player_playback_advancing"].waitForExistence(timeout: 15))
        XCTAssertTrue(waitForPlaybackTime(greaterThan: baseline + 0.5, in: app, timeout: 15))
        XCTAssertFalse(app.otherElements["player_error"].exists)
    }

    private func changeFocusedChoiceAndSelect(in app: XCUIApplication) throws -> String {
        let options = menuChoiceButtons(in: app)
        XCTAssertTrue(
            waitForMinimumCount(2, in: options, timeout: 5),
            "The live submenu must expose at least two real choices."
        )
        let focusMarker = app.otherElements["native_player_track_focused_title"]
        XCTAssertTrue(focusMarker.waitForExistence(timeout: 5))
        let optionElements = options.allElementsBoundByIndex
        XCTAssertTrue(
            waitForAnyValue(Set(optionElements.map(\.label)), on: focusMarker, timeout: 5),
            "The submenu must focus one of its real choices."
        )
        let originalLabel = focusMarker.value as? String ?? ""
        let focusedIndex = optionElements.firstIndex { $0.label == originalLabel }
        let moveButton: XCUIRemote.Button = focusedIndex == optionElements.indices.last ? .up : .down
        XCUIRemote.shared.press(moveButton)
        XCTAssertTrue(
            waitForDifferentValue(from: originalLabel, on: focusMarker, timeout: 5),
            "Remote vertical navigation must focus a different choice before Select."
        )
        XCUIRemote.shared.press(.select)
        return originalLabel
    }

    private func waitForMinimumCount(
        _ minimumCount: Int,
        in query: XCUIElementQuery,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in query.count >= minimumCount },
            object: nil
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func focusMenuRow(
        _ title: String,
        in app: XCUIApplication,
        using direction: XCUIRemote.Button,
        maximumMoves: Int
    ) {
        let focusMarker = app.otherElements["native_player_track_focused_title"]
        XCTAssertTrue(focusMarker.waitForExistence(timeout: 5))
        for _ in 0..<maximumMoves where (focusMarker.value as? String) != title {
            XCUIRemote.shared.press(direction)
        }
        XCTAssertTrue(waitForValue(title, on: focusMarker, timeout: 5))
    }

    private var selectedPredicate: NSPredicate {
        NSPredicate(format: "value == %@", "selected")
    }

    private func menuChoiceButtons(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(
            NSPredicate(
                format: "value == %@ OR value == %@",
                "selected",
                "not_selected"
            )
        )
    }

    private func selectedChoice(in app: XCUIApplication) -> XCUIElement {
        menuChoiceButtons(in: app).matching(selectedPredicate).firstMatch
    }

    private func revealChrome(in app: XCUIApplication) {
        if !app.otherElements["native_player_chrome"].exists { XCUIRemote.shared.press(.select) }
        XCTAssertTrue(app.otherElements["native_player_chrome"].waitForExistence(timeout: 5))
    }

    private func revealChromeAfterAutoHide(in app: XCUIApplication) {
        let chrome = app.otherElements["native_player_chrome"]
        if chrome.exists {
            XCTAssertTrue(waitForDisappearance(chrome, timeout: 5))
        }
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(chrome.waitForExistence(timeout: 5))
    }

    private func focusButton(_ identifier: String, in app: XCUIApplication, using directions: [XCUIRemote.Button]) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        for direction in directions where !button.hasFocus { XCUIRemote.shared.press(direction) }
        XCTAssertTrue(button.hasFocus, "Remote navigation did not focus \(identifier).")
    }

    private func waitForFocus(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in element.hasFocus },
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func dismissPlayerToDetail(in app: XCUIApplication) {
        for _ in 0..<3 where !app.otherElements["detail_screen"].exists { XCUIRemote.shared.press(.menu) }
    }

    private func playbackTime(in app: XCUIApplication) throws -> Double {
        let marker = app.otherElements["player_playback_time"].firstMatch
        guard marker.waitForExistence(timeout: 5),
              let string = marker.value as? String,
              let value = Double(string), value.isFinite else { throw JourneyError.invalidPlaybackTime }
        return value
    }

    private func waitForPlaybackTime(greaterThan threshold: Double, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? playbackTime(in: app)) ?? 0 > threshold { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return false
    }

    private func waitForTransport(_ expected: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        waitForValue(expected, on: app.otherElements["player_transport_state"].firstMatch, timeout: timeout)
    }

    private func waitForValue(_ expected: String, on element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.value as? String == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        return element.value as? String == expected
    }

    private func waitForAnyValue(_ expected: Set<String>, on element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = element.value as? String, expected.contains(value) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        guard let value = element.value as? String else { return false }
        return expected.contains(value)
    }

    private func waitForDifferentValue(from original: String, on element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = element.value as? String, !value.isEmpty, value != original { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        guard let value = element.value as? String else { return false }
        return !value.isEmpty && value != original
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        return !element.exists
    }

    private func liveConfiguration() -> [String: String] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent(".artifacts/player-e2e/tvos-live-ui.env")
        var values: [String: String] = [:]
        if let text = try? String(contentsOf: file, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) {
                let fields = line.split(separator: "=", maxSplits: 1).map(String.init)
                if fields.count == 2 { values[fields[0]] = fields[1] }
            }
        }
        for key in ["REELFIN_LIVE_UI_FIXTURE_ALIAS", "REELFIN_TV_UI_LOOP_COUNT"] {
            if let value = ProcessInfo.processInfo.environment[key] { values[key] = value }
        }
        return values
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        attachScreenshot(app.screenshot(), name: name)
    }

    private func attachScreenshot(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
