import XCTest

final class TVPlayerLiveUserJourneyTests: XCTestCase {
    private enum JourneyError: Error, LocalizedError {
        case missingFixture
        case invalidPlaybackTime
        case fixtureResolutionFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingFixture:
                return "Set REELFIN_LIVE_UI_TARGET_ITEM_ID (or TEST_STAR_CITY_EP1_ITEM_ID) to Star City episode 1 before running the live tvOS journey."
            case .invalidPlaybackTime:
                return "The player did not expose a finite numeric playback time."
            case .fixtureResolutionFailed(let reason):
                return "Could not resolve Star City season 1 episode 1 from the configured Jellyfin server: \(reason)"
            }
        }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testContinuePauseResumeSeekToZeroAndForward() throws {
        let app = try launchStarCityDetail()
        try startPlayback(in: app, choice: .continueDefault)
        try requireHealthyPlayback(in: app)

        let beforePause = try playbackTime(in: app)
        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(waitForTransport("paused", in: app, timeout: 8))
        let paused = try playbackTime(in: app)
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        let stillPaused = try playbackTime(in: app)
        XCTAssertEqual(stillPaused, paused, accuracy: 0.35)

        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(waitForTransport("playing", in: app, timeout: 12))
        XCTAssertTrue(waitForPlaybackTime(greaterThan: max(beforePause, paused) + 0.5, in: app, timeout: 15))

        let current = try playbackTime(in: app)
        let leftPressCount = max(1, Int(ceil(current / 10)))
        for _ in 0..<leftPressCount { XCUIRemote.shared.press(.left) }
        XCTAssertTrue(app.otherElements["player_seek_target_zero"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.otherElements["player_playback_advancing"].waitForExistence(timeout: 20))

        XCUIRemote.shared.press(.right)
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(app.otherElements["player_seek_completed"].waitForExistence(timeout: 15))
        XCTAssertTrue(waitForPlaybackTime(greaterThan: 20, in: app, timeout: 20))
        XCTAssertFalse(app.otherElements["player_error"].exists)
        attachScreenshot(app, name: "continue-pause-seek-complete")
    }

    func testAudioSubtitlesVideoPanelsAndMenuHierarchy() throws {
        let app = try launchStarCityDetail()
        try startPlayback(in: app, choice: .continueDefault)
        try requireHealthyPlayback(in: app)
        attachScreenshot(app, name: "player-hidden")
        revealChrome(in: app)
        attachScreenshot(app, name: "liquid-glass-chrome")

        focusButton(
            "native_player_subtitles_button",
            in: app,
            using: [.up, .left, .left, .right, .right]
        )
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["native_player_subtitles_menu"].waitForExistence(timeout: 8))
        assertStableTrackSelection(in: app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.otherElements["native_player_chrome"].waitForExistence(timeout: 5))

        focusButton("native_player_audio_button", in: app, using: [.right, .left, .right])
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["native_player_audio_menu"].waitForExistence(timeout: 8))
        assertStableTrackSelection(in: app)
        XCUIRemote.shared.press(.menu)

        focusButton("native_player_video_button", in: app, using: [.right, .right, .left, .right])
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["native_player_video_panel"].waitForExistence(timeout: 8))
        attachScreenshot(app, name: "video-panel")
        XCUIRemote.shared.press(.menu)

        focusButton(
            "native_player_info_button",
            in: app,
            using: [.down, .down, .left, .left, .left, .right]
        )
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["native_player_video_panel"].waitForExistence(timeout: 8))
        attachScreenshot(app, name: "info-panel")
        XCUIRemote.shared.press(.menu)

        focusButton("native_player_insight_button", in: app, using: [.right, .left, .right])
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["native_player_insight_panel"].waitForExistence(timeout: 8))
        attachScreenshot(app, name: "insight-panel")
        XCUIRemote.shared.press(.menu)

        focusButton(
            "native_player_continue_watching_button",
            in: app,
            using: [.right, .left, .right]
        )
        XCUIRemote.shared.press(.select)
        XCTAssertFalse(app.otherElements["native_player_chrome"].waitForExistence(timeout: 2))
        XCTAssertTrue(waitForTransport("playing", in: app, timeout: 8))

        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["native_player_chrome"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        XCTAssertFalse(app.otherElements["native_player_chrome"].waitForExistence(timeout: 2))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.otherElements["detail_screen"].waitForExistence(timeout: 12))
        XCTAssertTrue(waitForValue("primary_play_focused", on: app.otherElements["detail_screen"], timeout: 8))
    }

    func testRepeatedContinueAndRestartJourneysRemainHealthy() throws {
        let values = environmentValues()
        let loopCount = max(1, Int(values["REELFIN_TV_UI_LOOP_COUNT"] ?? "10") ?? 10)
        let app = try launchStarCityDetail()

        for iteration in 0..<loopCount {
            let choice: ResumeChoice = iteration.isMultiple(of: 2) ? .continueDefault : .restart
            try startPlayback(in: app, choice: choice)
            try requireHealthyPlayback(in: app)
            XCUIRemote.shared.press(.right)
            XCTAssertTrue(app.otherElements["player_seek_completed"].waitForExistence(timeout: 15))
            XCTAssertFalse(app.otherElements["player_error"].exists)
            dismissPlayerToDetail(in: app)
            XCTAssertTrue(app.otherElements["detail_screen"].waitForExistence(timeout: 12))
            attachScreenshot(app, name: "loop-\(iteration + 1)")
        }
    }

    private enum ResumeChoice { case continueDefault, restart }

    private func launchStarCityDetail() throws -> XCUIApplication {
        let fixtureID = try requiredFixtureID()
        let app = XCUIApplication()
        app.launchArguments += ["-reelfin-live-ui-open-target", fixtureID]
        app.launchEnvironment["REELFIN_LIVE_UI_TARGET_ITEM_ID"] = fixtureID
        app.launchEnvironment["REELFIN_LIVE_UI_OPEN_TARGET_DIRECTLY"] = "1"
        app.launchEnvironment["REELFIN_LIVE_UI_EXPECT_CUSTOM_CONTROLS"] = "1"
        // The simulator account may have marked this exact episode watched. Keep the authenticated
        // account untouched while exercising the real media from its known seven-minute position.
        app.launchEnvironment["REELFIN_LIVE_UI_RESUME_SECONDS"] = "440"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        XCTAssertTrue(
            app.otherElements["detail_screen"].waitForExistence(timeout: 45),
            "The authenticated simulator did not open the Star City episode 1 detail. Auth state must be preserved and supplied externally."
        )
        let primaryPlay = app.buttons["detail_primary_play_button"]
        XCTAssertTrue(primaryPlay.waitForExistence(timeout: 12))
        for _ in 0..<3 where !primaryPlay.hasFocus {
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(primaryPlay.hasFocus)
        XCTAssertTrue(waitForValue("primary_play_focused", on: app.otherElements["detail_screen"], timeout: 8))
        return app
    }

    private func startPlayback(in app: XCUIApplication, choice: ResumeChoice) throws {
        try focusAndSelectStarCityEpisodeOne(in: app)
        attachScreenshot(app, name: "after-episode-select")
        let choiceMarker = app.otherElements["playback_resume_choice"]
        XCTAssertTrue(choiceMarker.waitForExistence(timeout: 8), "Star City episode 1 must have meaningful resume progress for this journey.")
        XCTAssertTrue(waitForValue("resume_focused", on: choiceMarker, timeout: 5))
        if choice == .restart {
            XCUIRemote.shared.press(.right)
            XCTAssertTrue(waitForValue("restart_focused", on: choiceMarker, timeout: 5))
        }
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.otherElements["native_player_screen"].waitForExistence(timeout: 10))
    }

    private func focusAndSelectStarCityEpisodeOne(in app: XCUIApplication) throws {
        let episodeOne = app.buttons["detail_episode_1_1"]
        XCTAssertTrue(episodeOne.waitForExistence(timeout: 20))
        for _ in 0..<4 where !episodeOne.hasFocus {
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(episodeOne.hasFocus, "Remote navigation must focus Star City season 1 episode 1 before playback.")
        XCTAssertTrue((episodeOne.value as? String)?.hasPrefix("focused|") == true)
        XCUIRemote.shared.press(.select)
    }

    private func requireHealthyPlayback(in app: XCUIApplication) throws {
        XCTAssertTrue(app.otherElements["player_video_rendering_ready"].waitForExistence(timeout: 35))
        XCTAssertTrue(app.otherElements["player_audio_rendering_ready"].waitForExistence(timeout: 35))
        XCTAssertTrue(app.otherElements["player_playback_advancing"].waitForExistence(timeout: 35))
        XCTAssertTrue(app.otherElements["player_playback_time"].exists)
        XCTAssertTrue(app.otherElements["player_transport_state"].exists)
        XCTAssertFalse(app.otherElements["player_error"].exists)
        let generation = app.otherElements["native_player_reader_generation"].firstMatch
        if generation.exists {
            let value = generation.value as? String ?? ""
            XCTAssertNotNil(Int(value), "Reader generation evidence must be numeric and must not contain a media ID or URL.")
        }
    }

    private func revealChrome(in app: XCUIApplication) {
        if !app.otherElements["native_player_chrome"].exists {
            XCUIRemote.shared.press(.select)
        }
        XCTAssertTrue(app.otherElements["native_player_chrome"].waitForExistence(timeout: 5))
    }

    private func focusButton(
        _ identifier: String,
        in app: XCUIApplication,
        using directions: [XCUIRemote.Button]
    ) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        for direction in directions where !button.hasFocus {
            XCUIRemote.shared.press(direction)
        }
        XCTAssertTrue(button.hasFocus, "Remote navigation did not focus \(identifier).")
    }

    private func assertStableTrackSelection(in app: XCUIApplication) {
        let options = app.buttons.matching(identifier: "native_player_track_option")
        XCTAssertTrue(options.firstMatch.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(options.count, 0)
        XCTAssertEqual(
            options.matching(NSPredicate(format: "value == %@", "selected")).count,
            1,
            "Each track panel must expose exactly one authoritative selected option."
        )
    }

    private func dismissPlayerToDetail(in app: XCUIApplication) {
        if app.otherElements["native_player_audio_menu"].exists ||
            app.otherElements["native_player_subtitles_menu"].exists ||
            app.otherElements["native_player_video_panel"].exists {
            XCUIRemote.shared.press(.menu)
        }
        let chrome = app.otherElements["native_player_chrome"]
        if chrome.exists {
            XCUIRemote.shared.press(.menu)
            _ = waitForDisappearance(chrome, timeout: 5)
        }
        XCUIRemote.shared.press(.menu)
        if !app.otherElements["detail_screen"].waitForExistence(timeout: 5) {
            XCUIRemote.shared.press(.menu)
        }
    }

    private func playbackTime(in app: XCUIApplication) throws -> Double {
        let marker = app.otherElements["player_playback_time"].firstMatch
        guard marker.waitForExistence(timeout: 5),
              let string = marker.value as? String,
              let value = Double(string), value.isFinite else {
            throw JourneyError.invalidPlaybackTime
        }
        return value
    }

    private func waitForPlaybackTime(
        greaterThan threshold: Double,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? playbackTime(in: app)) ?? 0 > threshold { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return ((try? playbackTime(in: app)) ?? 0) > threshold
    }

    private func waitForTransport(_ expected: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let marker = app.otherElements["player_transport_state"].firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if marker.value as? String == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        return marker.value as? String == expected
    }

    private func waitForValue(_ expected: String, on element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.value as? String == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        return element.value as? String == expected
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        return !element.exists
    }

    private func requiredFixtureID() throws -> String {
        let values = environmentValues()
        for key in ["REELFIN_LIVE_UI_TARGET_ITEM_ID", "TEST_STAR_CITY_EP1_ITEM_ID"] {
            if let value = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        guard let baseURL = values["JELLYFIN_BASE_URL"],
              let username = values["JELLYFIN_USERNAME"],
              let password = values["JELLYFIN_PASSWORD"] else {
            throw JourneyError.missingFixture
        }
        return try resolveStarCityEpisodeOne(baseURL: baseURL, username: username, password: password)
    }

    private func resolveStarCityEpisodeOne(
        baseURL: String,
        username: String,
        password: String
    ) throws -> String {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var auth = URLRequest(url: try requiredURL("\(base)/Users/AuthenticateByName"))
        auth.httpMethod = "POST"
        auth.setValue("application/json", forHTTPHeaderField: "Content-Type")
        auth.setValue("ReelFin tvOS UI Tests", forHTTPHeaderField: "User-Agent")
        auth.setValue(jellyfinAuthorization(token: nil), forHTTPHeaderField: "X-Emby-Authorization")
        auth.httpBody = try JSONSerialization.data(withJSONObject: ["Username": username, "Pw": password])
        let authPayload = try send(auth)
        guard let authJSON = try JSONSerialization.jsonObject(with: authPayload) as? [String: Any],
              let user = authJSON["User"] as? [String: Any],
              let userID = user["Id"] as? String,
              let token = authJSON["AccessToken"] as? String else {
            throw JourneyError.fixtureResolutionFailed("invalid authentication response")
        }
        let session = (userID: userID, token: token)

        let series = try jellyfinItems(
            base: base,
            session: session,
            query: [
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "SearchTerm", value: "Star City"),
                URLQueryItem(name: "IncludeItemTypes", value: "Series")
            ]
        )
        guard let seriesID = series.first(where: {
            ($0["Name"] as? String)?.caseInsensitiveCompare("Star City") == .orderedSame
        })?["Id"] as? String else {
            throw JourneyError.fixtureResolutionFailed("series not found")
        }

        let episodes = try jellyfinItems(
            base: base,
            session: session,
            query: [
                URLQueryItem(name: "ParentId", value: seriesID),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "IncludeItemTypes", value: "Episode"),
                URLQueryItem(name: "Fields", value: "ParentIndexNumber,IndexNumber")
            ]
        )
        guard let episodeID = episodes.first(where: {
            ($0["ParentIndexNumber"] as? NSNumber)?.intValue == 1 &&
                ($0["IndexNumber"] as? NSNumber)?.intValue == 1
        })?["Id"] as? String else {
            throw JourneyError.fixtureResolutionFailed("season 1 episode 1 not found")
        }
        return episodeID
    }

    private func jellyfinItems(
        base: String,
        session: (userID: String, token: String),
        query: [URLQueryItem]
    ) throws -> [[String: Any]] {
        var components = URLComponents(string: "\(base)/Users/\(session.userID)/Items")
        components?.queryItems = query
        guard let url = components?.url else {
            throw JourneyError.fixtureResolutionFailed("invalid item query")
        }
        var request = URLRequest(url: url)
        request.setValue(session.token, forHTTPHeaderField: "X-Emby-Token")
        request.setValue(jellyfinAuthorization(token: session.token), forHTTPHeaderField: "X-Emby-Authorization")
        request.setValue("ReelFin tvOS UI Tests", forHTTPHeaderField: "User-Agent")
        let payload = try send(request)
        guard let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let items = json["Items"] as? [[String: Any]] else {
            throw JourneyError.fixtureResolutionFailed("invalid items response")
        }
        return items
    }

    private func send(_ request: URLRequest) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error>?
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                result = .failure(error)
                return
            }
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  let data else {
                result = .failure(JourneyError.fixtureResolutionFailed("HTTP request failed"))
                return
            }
            result = .success(data)
        }.resume()
        guard semaphore.wait(timeout: .now() + 30) == .success,
              let result else {
            throw JourneyError.fixtureResolutionFailed("request timed out")
        }
        return try result.get()
    }

    private func requiredURL(_ string: String) throws -> URL {
        guard let url = URL(string: string) else {
            throw JourneyError.fixtureResolutionFailed("invalid server URL")
        }
        return url
    }

    private func jellyfinAuthorization(token: String?) -> String {
        var value = "MediaBrowser Client=\"ReelFin\", Device=\"tvOS UI Tests\", DeviceId=\"reelfin-tvos-ui-tests\", Version=\"1.0\""
        if let token { value += ", Token=\"\(token)\"" }
        return value
    }

    private func environmentValues() -> [String: String] {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let envFile = repoRoot.appendingPathComponent(".artifacts/secrets/reelfin-e2e.env")
        var result: [String: String] = [:]
        if let text = try? String(contentsOf: envFile, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=") else { continue }
                let key = String(trimmed[..<separator])
                var value = String(trimmed[trimmed.index(after: separator)...])
                if value.first == value.last, value.first == "\"" || value.first == "'" {
                    value.removeFirst(); value.removeLast()
                }
                result[key] = value
            }
        }
        ProcessInfo.processInfo.environment.forEach { result[$0.key] = $0.value }
        return result
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
