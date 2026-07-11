import XCTest

/// Opt-in only. The test process receives no Jellyfin URL, credentials, token, user ID or item ID.
/// The already-authenticated DEBUG tvOS app resolves the redacted alias itself.
final class TVPlayerLiveUserJourneyTests: XCTestCase {
    private enum JourneyError: Error { case invalidPlaybackTime }
    private enum ResumeChoice: Equatable { case continueDefault, restart }

    private var requestedLoopCount = 10

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

        try changeAndRevalidateTrack(
            buttonID: "native_player_subtitles_button",
            menuID: "native_player_subtitles_menu",
            in: app,
            navigation: [.up]
        )
        try changeAndRevalidateTrack(
            buttonID: "native_player_audio_button",
            menuID: "native_player_audio_menu",
            in: app,
            navigation: [.right]
        )
        XCTAssertTrue(app.otherElements["player_audio_rendering_ready"].waitForExistence(timeout: 20))
        let audioRoute = app.otherElements["player_audio_rendering_ready"].value as? String
        XCTAssertTrue([
            "custom_avfoundation_selected_audible_advancing",
            "native_sample_buffer_audio_renderer_accepted"
        ].contains(audioRoute ?? ""))

        focusButton("native_player_video_button", in: app, using: [.right])
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["native_player_video_panel"].waitForExistence(timeout: 8))
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
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["native_player_screen"].waitForExistence(timeout: 12))
    }

    private func requireHealthyPlayback(in app: XCUIApplication) throws {
        XCTAssertTrue(app.otherElements["player_video_rendering_ready"].waitForExistence(timeout: 35))
        XCTAssertTrue(app.otherElements["player_audio_rendering_ready"].waitForExistence(timeout: 35))
        XCTAssertTrue(app.otherElements["player_playback_advancing"].waitForExistence(timeout: 35))
        XCTAssertFalse(app.otherElements["player_error"].exists)
        let generation = app.otherElements["native_player_reader_generation"].firstMatch
        if generation.exists { XCTAssertNotNil(Int(generation.value as? String ?? "")) }
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

    private func changeAndRevalidateTrack(
        buttonID: String,
        menuID: String,
        in app: XCUIApplication,
        navigation: [XCUIRemote.Button]
    ) throws {
        focusButton(buttonID, in: app, using: navigation)
        XCUIRemote.shared.press(.select)
        let menu = app.otherElements[menuID]
        XCTAssertTrue(menu.waitForExistence(timeout: 8))
        let options = app.buttons.matching(identifier: "native_player_track_option")
        XCTAssertGreaterThanOrEqual(
            options.count,
            2,
            "The live menu must expose at least one real alternate track in addition to the current choice."
        )
        let selected = options.matching(NSPredicate(format: "value == %@", "selected")).firstMatch
        XCTAssertTrue(selected.exists)
        let originalLabel = selected.label
        let optionElements = options.allElementsBoundByIndex
        let selectedIndex = optionElements.firstIndex { ($0.value as? String) == "selected" }
        let moveButton: XCUIRemote.Button = selectedIndex == optionElements.indices.last ? .up : .down
        let focusMarker = app.otherElements["native_player_track_focused_title"]
        XCTAssertTrue(focusMarker.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(originalLabel, on: focusMarker, timeout: 5))
        XCUIRemote.shared.press(moveButton)
        XCTAssertTrue(
            waitForDifferentValue(from: originalLabel, on: focusMarker, timeout: 5),
            "Remote vertical navigation must visibly focus a different real track before Select."
        )
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForDisappearance(menu, timeout: 8))

        focusButton(buttonID, in: app, using: navigation)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(menu.waitForExistence(timeout: 8))
        let changed = app.buttons.matching(identifier: "native_player_track_option")
            .matching(NSPredicate(format: "value == %@", "selected")).firstMatch
        XCTAssertTrue(changed.exists)
        XCTAssertNotEqual(changed.label, originalLabel)
        XCTAssertEqual(options.matching(NSPredicate(format: "value == %@", "selected")).count, 1)
        XCUIRemote.shared.press(.menu)
    }

    private func revealChrome(in app: XCUIApplication) {
        if !app.otherElements["native_player_chrome"].exists { XCUIRemote.shared.press(.select) }
        XCTAssertTrue(app.otherElements["native_player_chrome"].waitForExistence(timeout: 5))
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
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
