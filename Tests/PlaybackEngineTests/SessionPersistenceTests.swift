import JellyfinAPI
import PlaybackEngine
import Foundation
import Shared
import XCTest

final class SessionPersistenceTests: XCTestCase {
    func testCurrentSessionDoesNotRestoreFromSettingsStoreWithoutKeychainToken() async {
        let savedSession = UserSession(userID: "u1", username: "Flo", token: "")
        let settings = MockSettingsStore(
            serverConfiguration: ServerConfiguration(serverURL: URL(string: "https://example.com")!),
            lastSession: savedSession
        )
        let tokenStore = MockTokenStore(storedToken: nil)

        let client = JellyfinAPIClient(tokenStore: tokenStore, settingsStore: settings)
        let restored = await client.currentSession()

        XCTAssertNil(restored)
    }

    func testCurrentSessionUsesKeychainTokenWhenAvailable() async {
        let savedSession = UserSession(userID: "u1", username: "Flo", token: "")
        let settings = MockSettingsStore(
            serverConfiguration: ServerConfiguration(serverURL: URL(string: "https://example.com")!),
            lastSession: savedSession
        )
        let tokenStore = MockTokenStore(storedToken: "token-from-keychain")

        let client = JellyfinAPIClient(tokenStore: tokenStore, settingsStore: settings)
        let restored = await client.currentSession()

        XCTAssertEqual(restored?.userID, "u1")
        XCTAssertEqual(restored?.username, "Flo")
        XCTAssertEqual(restored?.token, "token-from-keychain")
    }
}

private final class MockSettingsStore: SettingsStoreProtocol, @unchecked Sendable {
    var serverConfiguration: ServerConfiguration?
    var lastSession: UserSession?
    var episodeReleaseNotificationsEnabled = false
    var hasCompletedOnboarding = false
    var completedOnboardingVersion = 0

    init(serverConfiguration: ServerConfiguration?, lastSession: UserSession?) {
        self.serverConfiguration = serverConfiguration
        self.lastSession = lastSession
    }
}

private final class MockTokenStore: TokenStoreProtocol, @unchecked Sendable {
    var storedToken: String?

    init(storedToken: String?) {
        self.storedToken = storedToken
    }

    func saveToken(_ token: String) throws {
        storedToken = token
    }

    func fetchToken() throws -> String? {
        storedToken
    }

    func clearToken() throws {
        storedToken = nil
    }
}

final class PlaybackIntegrationProbeTests: XCTestCase {
    func testLiveServerPlaybackProbeLoop() async throws {
        let environment = liveEnvironment()
        guard
            let serverURLString = environment["REELFIN_TEST_SERVER_URL"],
            let serverURL = URL(string: serverURLString),
            let username = environment["REELFIN_TEST_USERNAME"],
            let password = environment["REELFIN_TEST_PASSWORD"]
        else {
            throw XCTSkip("Set REELFIN_TEST_SERVER_URL / REELFIN_TEST_USERNAME / REELFIN_TEST_PASSWORD to run live playback probes.")
        }

        let loops = max(1, Int(environment["REELFIN_TEST_LOOPS"] ?? "2") ?? 2)
        let sampleSize = max(1, Int(environment["REELFIN_TEST_SAMPLE_SIZE"] ?? "8") ?? 8)
        let maxFailures = max(0, Int(environment["REELFIN_TEST_MAX_FAILURES"] ?? "0") ?? 0)
        let explicitOnly = isEnabled(environment["REELFIN_TEST_EXPLICIT_ONLY"])

        let settings = MockSettingsStore(
            serverConfiguration: nil,
            lastSession: nil
        )
        let tokenStore = MockTokenStore(storedToken: nil)
        let client = JellyfinAPIClient(tokenStore: tokenStore, settingsStore: settings)
        let coordinator = PlaybackCoordinator(apiClient: client)

        try await client.configure(server: ServerConfiguration(serverURL: serverURL))
        _ = try await client.authenticate(credentials: UserCredentials(username: username, password: password))

        var total = 0
        var failures = 0
        var failureLines: [String] = []

        let explicitItems = explicitLiveItems(environment: environment)

        for loopIndex in 1 ... loops {
            let feed = try await client.fetchHomeFeed(since: nil)
            let items = collectItems(
                feed: feed,
                explicitItems: explicitItems,
                maxItems: sampleSize,
                explicitOnly: explicitOnly
            )

            for item in items {
                total += 1

                do {
                    let selection = try await coordinator.resolvePlayback(
                        itemID: item.id,
                        mode: .balanced,
                        allowTranscodingFallbackInPerformance: true
                    )

                    let reachable = try await probeSelection(selection)
                    if !reachable {
                        failures += 1
                        failureLines.append("loop=\(loopIndex) item=\(item.name) method=\(selection.debugInfo.playMethod) reason=probe_failed")
                    }
                } catch {
                    failures += 1
                    failureLines.append("loop=\(loopIndex) item=\(item.name) reason=\(error.localizedDescription)")
                }
            }
        }

        let summary = "Live probe summary: \(total - failures)/\(total) passed, \(failures) failed (allowed: \(maxFailures))."
        XCTContext.runActivity(named: summary) { activity in
            if !failureLines.isEmpty {
                activity.add(XCTAttachment(string: failureLines.joined(separator: "\n")))
            }
        }

        XCTAssertLessThanOrEqual(failures, maxFailures, summary)
    }

    private func collectItems(
        feed: HomeFeed,
        explicitItems: [MediaItem],
        maxItems: Int,
        explicitOnly: Bool
    ) -> [MediaItem] {
        if explicitOnly {
            return Array(explicitItems.prefix(maxItems))
        }

        var ordered = explicitItems
        var seen = Set(explicitItems.map(\.id))

        for item in feed.featured where seen.insert(item.id).inserted {
            ordered.append(item)
            if ordered.count >= maxItems { return ordered }
        }

        for row in feed.rows {
            for item in row.items where seen.insert(item.id).inserted {
                ordered.append(item)
                if ordered.count >= maxItems { return ordered }
            }
        }

        return ordered
    }

    private func explicitLiveItems(environment: [String: String]) -> [MediaItem] {
        let directPlayPair = ("directplay_mp4", environment["TEST_DIRECTPLAY_MP4_ITEM_ID"])
        let pairs = isEnabled(environment["REELFIN_TEST_DIRECTPLAY_ONLY"]) ? [
            directPlayPair,
        ] : [
            directPlayPair,
            ("mkv_original", environment["TEST_MKV_ITEM_ID"] ?? environment["TEST_MKV_DOLBY_VISION_ITEM_ID"]),
            (
                "dolby_vision_original",
                environment["TEST_DOLBY_VISION_ITEM_ID"]
                    ?? environment["TEST_DIRECTPLAY_DOLBY_VISION_ITEM_ID"]
                    ?? environment["TEST_MKV_DOLBY_VISION_ITEM_ID"]
            ),
        ]
        var seen = Set<String>()
        return pairs.compactMap { name, rawValue in
            guard
                let id = normalizedJellyfinID(rawValue),
                seen.insert(id).inserted
            else { return nil }
            return MediaItem(id: id, name: name)
        }
    }

    private func normalizedJellyfinID(_ rawValue: String?) -> String? {
        guard let rawValue, !rawValue.isEmpty, rawValue != "..." else { return nil }
        let patterns = [
            #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#,
            #"[0-9a-fA-F]{32}"#,
        ]
        for pattern in patterns {
            if let range = rawValue.range(of: pattern, options: .regularExpression) {
                return String(rawValue[range])
            }
        }
        return rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func liveEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        loadEnvFile().forEach { key, value in
            environment[key] = environment[key] ?? value
        }
        let simulatorChildKeys = [
            "REELFIN_TEST_SERVER_URL",
            "REELFIN_TEST_USERNAME",
            "REELFIN_TEST_PASSWORD",
            "REELFIN_TEST_LOOPS",
            "REELFIN_TEST_SAMPLE_SIZE",
            "REELFIN_TEST_MAX_FAILURES",
            "REELFIN_TEST_EXPLICIT_ONLY",
            "REELFIN_TEST_DIRECTPLAY_ONLY",
            "TEST_DIRECTPLAY_MP4_ITEM_ID",
            "TEST_MKV_ITEM_ID",
            "TEST_HDR_ITEM_ID",
            "TEST_DOLBY_VISION_ITEM_ID",
        ]
        for key in simulatorChildKeys {
            environment[key] = environment[key] ?? environment["SIMCTL_CHILD_\(key)"]
        }
        environment["REELFIN_TEST_SERVER_URL"] = environment["REELFIN_TEST_SERVER_URL"] ?? environment["JELLYFIN_BASE_URL"]
        environment["REELFIN_TEST_USERNAME"] = environment["REELFIN_TEST_USERNAME"] ?? environment["JELLYFIN_USERNAME"]
        environment["REELFIN_TEST_PASSWORD"] = environment["REELFIN_TEST_PASSWORD"] ?? environment["JELLYFIN_PASSWORD"]
        environment["TEST_MKV_ITEM_ID"] = environment["TEST_MKV_ITEM_ID"] ?? environment["TEST_MKV_DOLBY_VISION_ITEM_ID"]
        environment["TEST_DOLBY_VISION_ITEM_ID"] = environment["TEST_DOLBY_VISION_ITEM_ID"]
            ?? environment["TEST_DIRECTPLAY_DOLBY_VISION_ITEM_ID"]
            ?? environment["TEST_MKV_DOLBY_VISION_ITEM_ID"]
        environment["REELFIN_TEST_LOOPS"] = environment["REELFIN_TEST_LOOPS"] ?? "1"
        environment["REELFIN_TEST_SAMPLE_SIZE"] = environment["REELFIN_TEST_SAMPLE_SIZE"] ?? "1"
        environment["REELFIN_TEST_EXPLICIT_ONLY"] = environment["REELFIN_TEST_EXPLICIT_ONLY"] ?? "1"
        environment["REELFIN_TEST_DIRECTPLAY_ONLY"] = environment["REELFIN_TEST_DIRECTPLAY_ONLY"] ?? "1"
        return environment
    }

    private func isEnabled(_ value: String?) -> Bool {
        guard let value else { return false }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on":
            return true
        default:
            return false
        }
    }

    private func loadEnvFile() -> [String: String] {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let envURL = repoRoot.appendingPathComponent(".artifacts/secrets/reelfin-e2e.env")
        guard let content = try? String(contentsOf: envURL, encoding: .utf8) else { return [:] }

        var values: [String: String] = [:]
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else { continue }
            var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               let quote = value.first,
               quote == value.last,
               quote == "\"" || quote == "'" {
                value.removeFirst()
                value.removeLast()
            }
            values[key] = String(value)
        }
        return values
    }

    private func probeSelection(_ selection: PlaybackAssetSelection) async throws -> Bool {
        guard case .transcode = selection.decision.route else {
            return try await probeBinary(url: selection.assetURL, headers: selection.headers)
        }

        let master = try await fetchManifest(url: selection.assetURL, headers: selection.headers)
        guard
            let firstLine = firstMediaLine(in: master),
            let firstURL = resolveLine(firstLine, baseURL: selection.assetURL)
        else {
            return false
        }

        if firstURL.pathExtension.lowercased() == "m3u8" {
            let child = try await fetchManifest(url: firstURL, headers: selection.headers)
            guard
                let childLine = firstMediaLine(in: child),
                let segmentURL = resolveLine(childLine, baseURL: firstURL)
            else {
                return false
            }
            return try await probeBinary(url: segmentURL, headers: selection.headers)
        }

        return try await probeBinary(url: firstURL, headers: selection.headers)
    }

    private func fetchManifest(url: URL, headers: [String: String]) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/vnd.apple.mpegurl,application/x-mpegURL,*/*", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            return ""
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    private func probeBinary(url: URL, headers: [String: String]) async throws -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("bytes=0-2047", forHTTPHeaderField: "Range")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { return false }
        guard (200 ..< 300).contains(http.statusCode) || http.statusCode == 206 else { return false }
        for try await _ in bytes {
            return true
        }
        return false
    }

    private func firstMediaLine(in manifest: String) -> String? {
        manifest
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.isEmpty && !$0.hasPrefix("#") })
    }

    private func resolveLine(_ line: String, baseURL: URL) -> URL? {
        if let absolute = URL(string: line), absolute.scheme != nil {
            return absolute
        }

        guard let resolved = URL(string: line, relativeTo: baseURL)?.absoluteURL else {
            return nil
        }

        guard
            let baseComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
            let apiKey = baseComponents.queryItems?.first(where: { $0.name.caseInsensitiveCompare("api_key") == .orderedSame })?.value
        else {
            return resolved
        }

        guard var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false) else {
            return resolved
        }

        var queryItems = components.queryItems ?? []
        if !queryItems.contains(where: { $0.name.caseInsensitiveCompare("api_key") == .orderedSame }) {
            queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
            components.queryItems = queryItems
        }
        return components.url ?? resolved
    }
}
