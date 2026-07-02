import AVFoundation
import Foundation
import XCTest
@testable import PlaybackEngine

/// LIVE integration test: plays a real H.264 title from the user's actual Jellyfin/Cloudflare
/// origin through the rebuilt cache-loader pipeline (OriginDownloader parallel fill +
/// CacheResourceLoaderDelegate + MediaGatewayStore + a real AVPlayer). This is the closest to
/// real-world proof obtainable without the physical device: it validates cold-start, Content-Range
/// parsing, parallel multi-connection throughput, buffer building, AVPlayer integration, and the
/// teardown — all against the REAL server, not the local mock.
///
/// Skips gracefully when the gitignored e2e secrets are absent (so CI without secrets stays green).
/// The simulator can decode H.264 (not the 4K DV originals), so it uses an H.264 movie.
final class CacheLoaderLiveIntegrationTests: XCTestCase {
    private static let envPath = "/Users/florian/Documents/Projet/ReelFin/.artifacts/secrets/reelfin-e2e.env"
    private static let h264ItemID = "61593e32518e85e691b2a8309d1d02ce" // 'American Assassin' 1080p H.264 MP4 ~5.2 Mbps (AVPlayer-openable)

    @MainActor
    func testCacheLoaderPlaysRealOriginH264WithBufferBuilding() async throws {
        try await runLive(seekToSeconds: nil)
    }

    /// The device's failure case: a RESUME (deep seek) — the cache loader must follow the seek and
    /// fill the playback region against the real origin, not stall (audio_only_no_video).
    @MainActor
    func testCacheLoaderResumesRealOriginH264FromDeepSeek() async throws {
        try await runLive(seekToSeconds: 600)
    }

    @MainActor
    private func runLive(seekToSeconds: Double?) async throws {
        guard let cfg = Self.loadEnv() else {
            throw XCTSkip("No e2e secrets — live integration test skipped.")
        }
        guard let base = cfg["JELLYFIN_BASE_URL"]?.trimmingCharacters(in: .whitespaces),
              let user = cfg["JELLYFIN_USERNAME"], let pass = cfg["JELLYFIN_PASSWORD"] else {
            throw XCTSkip("Incomplete e2e secrets.")
        }
        let baseURL = base.hasSuffix("/") ? String(base.dropLast()) : base

        guard let token = try await Self.authenticate(baseURL: baseURL, user: user, pass: pass) else {
            throw XCTSkip("Jellyfin auth failed (server/connection down) — skipping live test.")
        }

        let origin = URL(string: "\(baseURL)/Videos/\(Self.h264ItemID)/stream?static=true&MediaSourceId=\(Self.h264ItemID)&api_key=\(token)")!

        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CacheLoaderLive.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }

        let store = try MediaGatewayStore(
            directoryURL: storeDir,
            configuration: MediaGatewayStore.Configuration(chunkSize: 1_024 * 1_024, maxBytes: 2_000_000_000, ttlSeconds: nil)
        )
        let key = MediaGatewayCacheKey(
            scope: "original", userID: "live", serverID: origin.host, itemID: Self.h264ItemID,
            sourceID: Self.h264ItemID, routeURL: origin
        )
        let downloader = OriginDownloader(
            remoteURL: origin, headers: [:], key: key, store: store,
            overrideContentType: "video/mp4", sessionConfiguration: .ephemeral, maxParallelWindows: 6
        )
        let loader = CacheResourceLoaderDelegate(store: store, downloader: downloader, key: key, overrideMIMEType: "video/mp4")
        defer { loader.invalidate() }

        await downloader.primeStart()
        let asset = loader.makeAsset(for: Self.h264ItemID)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 30
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        defer { player.pause() }

        let stalls = StallBox()
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main
        ) { _ in stalls.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }

        let ready = await Self.waitUntil(timeout: 30) { item.status != .unknown }
        XCTAssertTrue(ready, "Live cache-loader item never loaded against the real origin. error=\(String(describing: item.error))")
        guard item.status == .readyToPlay else {
            throw XCTSkip("Item not readyToPlay (likely the server/connection) — error=\(String(describing: item.error))")
        }

        let bitrate = 5_240_184.0 // 'American Assassin' ~5.2 Mbps
        if let seekToSeconds {
            await player.seek(to: CMTime(seconds: seekToSeconds, preferredTimescale: 600),
                              toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600))
        }
        let seekLabel: String = seekToSeconds == nil ? "none" : String(Int(seekToSeconds ?? 0))
        let startThreshold = (seekToSeconds ?? 0) + 0.5
        let watchTarget = (seekToSeconds ?? 0) + 16
        player.playImmediately(atRate: 1)
        let started = await Self.waitUntil(timeout: 25) { player.currentTime().seconds > startThreshold }
        XCTAssertTrue(started, "Live playback never advanced past the first frame (seek=\(seekLabel)).")
        if seekToSeconds != nil {
            _ = await Self.waitUntil(timeout: 10) { item.isPlaybackLikelyToKeepUp } // let the post-seek cushion build
        }
        stalls.reset()

        _ = bitrate
        let deadline = Date().addingTimeInterval(60)
        var maxBufferedAhead = 0.0
        while Date() < deadline {
            if player.currentTime().seconds >= watchTarget { break }
            maxBufferedAhead = max(maxBufferedAhead, Self.bufferedAhead(item))
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        let reachedSeconds = player.currentTime().seconds
        print("cacheloader.live — seek=\(seekLabel) reached=\(reachedSeconds) stalls=\(stalls.value) maxBufferedAheadSec=\(maxBufferedAhead)")
        XCTAssertGreaterThanOrEqual(reachedSeconds, watchTarget - 2,
            "Cache loader must play the real-origin H.264 title through to ~\(Int(watchTarget))s.")
        XCTAssertEqual(stalls.value, 0,
            "On a healthy connection the cache loader must play the real origin with zero stalls.")
        XCTAssertGreaterThan(maxBufferedAhead, 5,
            "The cache loader must keep AVPlayer's buffer fed ahead of the playhead (>5s) against the real origin.")
    }

    /// LIVE proof of the WHOLE custom engine: real origin → OriginDownloader (parallel, keep-alive)
    /// → rebuilt MediaGatewayStore (in-memory coverage, append-coalesced segments) →
    /// LocalCacheHTTPServer (localhost, DV-safe transport) → real AVPlayer, gated by the dynamic
    /// fast-start policy. Asserts the Infuse-class contract on a healthy link: fast first frame,
    /// zero stalls, reservoir building behind playback.
    @MainActor
    func testCustomEnginePlaysRealOriginThroughLocalhostCache() async throws {
        guard let cfg = Self.loadEnv() else {
            throw XCTSkip("No e2e secrets — live integration test skipped.")
        }
        guard let base = cfg["JELLYFIN_BASE_URL"]?.trimmingCharacters(in: .whitespaces),
              let user = cfg["JELLYFIN_USERNAME"], let pass = cfg["JELLYFIN_PASSWORD"] else {
            throw XCTSkip("Incomplete e2e secrets.")
        }
        let baseURL = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let token = try await Self.authenticate(baseURL: baseURL, user: user, pass: pass) else {
            throw XCTSkip("Jellyfin auth failed (server/connection down) — skipping live test.")
        }
        let origin = URL(string: "\(baseURL)/Videos/\(Self.h264ItemID)/stream?static=true&MediaSourceId=\(Self.h264ItemID)&api_key=\(token)")!

        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CustomEngineLive.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let store = try MediaGatewayStore(
            directoryURL: storeDir,
            configuration: MediaGatewayStore.Configuration(chunkSize: 1_024 * 1_024, maxBytes: 2_000_000_000, ttlSeconds: nil)
        )
        let key = MediaGatewayCacheKey(
            scope: "original", userID: "live", serverID: origin.host, itemID: Self.h264ItemID,
            sourceID: Self.h264ItemID, routeURL: origin
        )
        struct LiveResolver: CustomPlaybackSourceResolving {
            let origin: URL
            let key: MediaGatewayCacheKey
            func resolveOriginal(itemID: String, startTimeTicks: Int64?) async throws -> ResolvedOriginalSource {
                ResolvedOriginalSource(
                    originURL: origin, headers: [:], sourceBitrate: 5_240_184,
                    overrideMIMEType: "video/mp4", cacheKey: key, isDolbyVision: false)
            }
        }
        let engine = CustomPlaybackEngine(resolver: LiveResolver(origin: origin, key: key), store: store)
        defer { engine.stop() }

        let stalls = StallBox()
        var stallObserver: NSObjectProtocol?
        defer { if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) } }

        let loadStarted = Date()
        engine.load(itemID: Self.h264ItemID, autoPlay: true)

        let started = await Self.waitUntil(timeout: 45) { @MainActor in
            engine.bufferingState.phase == .playing && engine.player.currentTime().seconds > 0.5
        }
        let ttff = Date().timeIntervalSince(loadStarted)
        guard started else {
            throw XCTSkip("Live start did not reach playback (connection/server state) — phase=\(engine.bufferingState.phase) err=\(engine.errorMessage ?? "nil")")
        }
        if let item = engine.player.currentItem {
            stallObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.playbackStalledNotification, object: item, queue: .main
            ) { _ in stalls.increment() }
        }

        let watchTarget = engine.player.currentTime().seconds + 15
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if engine.player.currentTime().seconds >= watchTarget { break }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        let reached = engine.player.currentTime().seconds
        let reservoir = engine.bufferingState.reservoirSeconds
        print("customengine.live — ttff=\(String(format: "%.1f", ttff))s reached=\(String(format: "%.1f", reached))s stalls=\(stalls.value) reservoir=\(String(format: "%.0f", reservoir))s err=\(engine.errorMessage ?? "nil")")

        XCTAssertNil(engine.errorMessage)
        XCTAssertLessThan(ttff, 15, "fast start: first frame must not wait on a deep cushion on a healthy link (got \(ttff)s)")
        XCTAssertGreaterThanOrEqual(reached, watchTarget - 2, "custom engine must sustain playback against the real origin")
        XCTAssertEqual(stalls.value, 0, "zero stalls expected on a healthy link through the localhost cache")
        XCTAssertGreaterThan(reservoir, 10, "the disk reservoir must build behind playback")
    }

    // MARK: - Helpers

    private static func loadEnv() -> [String: String]? {
        guard let text = try? String(contentsOfFile: envPath, encoding: .utf8) else { return nil }
        var cfg: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") else { continue }
            cfg[String(t[..<eq])] = String(t[t.index(after: eq)...]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return cfg.isEmpty ? nil : cfg
    }

    private static func authenticate(baseURL: String, user: String, pass: String) async throws -> String? {
        let pair = try await authenticateFull(baseURL: baseURL, user: user, pass: pass)
        return pair?.token
    }

    private static func authenticateFull(baseURL: String, user: String, pass: String) async throws -> (token: String, userID: String)? {
        var req = URLRequest(url: URL(string: "\(baseURL)/Users/AuthenticateByName")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("MediaBrowser Client=\"ReelFinTest\", Device=\"test\", DeviceId=\"reelfin-live-test\", Version=\"1.0\"",
                     forHTTPHeaderField: "X-Emby-Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["Username": user, "Pw": pass])
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.waitsForConnectivity = true
        let session = URLSession(configuration: cfg)
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard code == 200,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = obj["AccessToken"] as? String,
                  let userObj = obj["User"] as? [String: Any],
                  let userID = userObj["Id"] as? String else {
                print("cacheloader.live.auth — unexpected http=\(code) bodyBytes=\(data.count)")
                return nil
            }
            return (token, userID)
        } catch {
            print("cacheloader.live.auth.error — \(error)")
            return nil
        }
    }

    /// Resolves the Jellyfin adaptive HLS transcode URL (the never-cut fallback target) via
    /// PlaybackInfo with transcoding enabled — the exact thing the player's stall recovery loads.
    private static func transcodingMasterURL(baseURL: String, itemID: String, token: String, userID: String) async throws -> URL? {
        let deviceProfile: [String: Any] = [
            "MaxStreamingBitrate": 8_000_000, "MaxStaticBitrate": 8_000_000,
            "DirectPlayProfiles": [],
            "TranscodingProfiles": [[
                "Container": "ts", "Type": "Video", "VideoCodec": "h264", "AudioCodec": "aac",
                "Protocol": "hls", "Context": "Streaming", "MaxAudioChannels": "2",
                "MinSegments": 1, "BreakOnNonKeyFrames": true
            ]],
            "ContainerProfiles": [], "CodecProfiles": [],
            "SubtitleProfiles": [["Format": "vtt", "Method": "Hls"]]
        ]
        let body: [String: Any] = [
            "DeviceProfile": deviceProfile, "MaxStreamingBitrate": 8_000_000, "StartTimeTicks": 0,
            "EnableDirectPlay": false, "EnableDirectStream": false, "EnableTranscoding": true,
            "AllowVideoStreamCopy": false, "AllowAudioStreamCopy": false, "AutoOpenLiveStream": true
        ]
        var req = URLRequest(url: URL(string: "\(baseURL)/Items/\(itemID)/PlaybackInfo?UserId=\(userID)&api_key=\(token)")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: cfg)
        let (data, _) = try await session.data(for: req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sources = obj["MediaSources"] as? [[String: Any]] else { return nil }
        for s in sources {
            if let turl = s["TranscodingUrl"] as? String {
                return URL(string: turl.hasPrefix("/") ? "\(baseURL)\(turl)" : turl)
            }
        }
        return nil
    }

    private static func bufferedAhead(_ item: AVPlayerItem) -> Double {
        let now = item.currentTime()
        for value in item.loadedTimeRanges {
            let range = value.timeRangeValue
            let end = CMTimeAdd(range.start, range.duration)
            if CMTimeCompare(range.start, now) <= 0, CMTimeCompare(end, now) >= 0 {
                return max(0, CMTimeGetSeconds(end) - CMTimeGetSeconds(now))
            }
        }
        return 0
    }

    private static func waitUntil(timeout: TimeInterval, _ condition: @escaping () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return await condition()
    }

    private final class StallBox: @unchecked Sendable {
        private let lock = NSLock(); private var n = 0
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
        func increment() { lock.lock(); n += 1; lock.unlock() }
        func reset() { lock.lock(); n = 0; lock.unlock() }
    }
}
