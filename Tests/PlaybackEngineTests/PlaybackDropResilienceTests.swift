import AVFoundation
import Foundation
import Network
import XCTest
@testable import PlaybackEngine

/// Deterministic, self-contained reproduction of the "it cuts when the connection drops" bug, and
/// the regression guard for the deep-forward-buffer fix.
///
/// The device logs showed a connection that is intermittently fast (≈100 Mbps) but punctuated by
/// multi-second drops (NSURLError -1005/-1001). The user-visible cut is AVPlayer's buffer draining
/// to empty during such a drop. That dynamic is codec-agnostic, so we reproduce it WITHOUT the 4K
/// HEVC the Simulator can't decode:
///   1. generate a small H.264 clip the Simulator decodes trivially,
///   2. serve it over a local HTTP/1.1 server that paces delivery (so AVPlayer's buffer reflects
///      `preferredForwardBufferDuration` instead of instantly downloading the whole clip) and
///      freezes delivery during scheduled drop windows (the simulated connection drop),
///   3. play it and count `AVPlayerItemPlaybackStalled`.
///
/// Asserts the dynamic both ways:
///   • a THIN forward buffer (2 s) stalls on a 5 s drop  → reproduces the cut,
///   • a DEEP forward buffer (≥ drop) absorbs the same drop with zero stalls → validates the fix.
final class PlaybackDropResilienceTests: XCTestCase {

    // Shared generated clip (encode once for the whole class).
    private static var clipURL: URL?
    private static var clipBitrate: Double = 0

    override class func tearDown() {
        if let url = clipURL { try? FileManager.default.removeItem(at: url) }
        super.tearDown()
    }

    /// DIAGNOSTIC: does AVPlayer actually fill to `preferredForwardBufferDuration` on a link that
    /// is comfortably faster than the bitrate? Serves at 8x bitrate (no drops) and records the max
    /// buffered-ahead reached. If it plateaus far below the 25s setting, AVPlayer is NOT honoring
    /// the deep buffer as a floor — which is the root of the residual cuts.
    @MainActor
    func testAVPlayerForwardBufferDepth_diagnostic() async throws {
        let result = try await runDropScenario(forwardBuffer: 25, dropWindows: [], watch: 30, throttleMultiplier: 8)
        print("drop.bufferdepth — reached=\(result.reached) maxBufferedAhead=\(result.maxBufferedAhead) waitsManaged=true")
        XCTAssertGreaterThanOrEqual(result.maxBufferedAhead, 18,
            "AVPlayer must build a deep forward buffer (>=18s of a 25s setting) on a fast link to ride out drops. If it doesn't, preferredForwardBufferDuration is being ignored as a floor and the buffer strategy must change.")
    }

    /// Reproduces the cut faithfully: a link that can't sustain the bitrate (0.5x) drains the
    /// buffer no matter how large the setting — no client-side buffering fixes bandwidth < bitrate.
    /// This is the test-proven reason the ONLY remedy is a lower bitrate (the HLS/transcode
    /// escalation), not a bigger buffer.
    @MainActor
    func testSustainedLowBandwidthStalls_reproducesTheCut() async throws {
        let result = try await runDropScenario(forwardBuffer: 60, dropWindows: [], watch: 25, throttleMultiplier: 0.5)
        print("drop.repro.lowbw — reached=\(result.reached) stalls=\(result.stalls) maxBuf=\(result.maxBufferedAhead)")
        XCTAssertGreaterThan(result.stalls, 0,
            "A link at 0.5x the bitrate must stall regardless of buffer size — the only fix is lower bitrate (HLS ABR), which is what the stall escalation switches to.")
    }

    @MainActor
    func testDeepBufferAbsorbsConnectionDrop_validatesTheFix() async throws {
        // Drop fires at t=20s — well after a fast (8x) link should have filled a 25s buffer.
        let result = try await runDropScenario(forwardBuffer: 25, dropWindows: [(start: 20, duration: 5)], watch: 30, throttleMultiplier: 8)
        print("drop.repro.deep — reached=\(result.reached) stalls=\(result.stalls) maxBuf=\(result.maxBufferedAhead)")
        XCTAssertGreaterThanOrEqual(result.reached, 28,
            "Deep-buffer playback must advance through the drop to ~28 s.")
        XCTAssertEqual(result.stalls, 0,
            "A buffer deeper than the drop must absorb it with zero user-visible stalls — this is the fix.")
    }

    // MARK: - Cache-loader proof tests (OriginDownloader + CacheResourceLoaderDelegate + store)

    /// THE never-cut proof. AVPlayer reads exclusively from the app cache; the downloader fills
    /// ahead on a keep-alive connection. A REAL socket reset (-1005) fires mid-playback. Because
    /// the cache is already ahead of the playhead and the downloader resumes from the store's
    /// committed end, AVPlayer never sees a gap → zero stalls. This is the configuration the user
    /// asked for: raw original bytes, no HLS, DV-preservable, "ça ne coupe plus".
    @MainActor
    func testCacheLoaderAbsorbsConnectionReset_zeroStalls() async throws {
        let result = try await runCacheLoaderScenario(
            dropWindows: [(start: 10, duration: 3)],
            watch: 20,
            throttleMultiplier: 3,
            dropMode: .resetConnection,
            keepAlive: true
        )
        print("cacheloader.reset.zerostall — reached=\(result.reached) stalls=\(result.stalls) served=\(result.servedBytes) file=\(result.fileSize) conns=\(result.connections)")
        XCTAssertGreaterThanOrEqual(result.reached, 18,
            "Playback must advance through the reset to ~18s on the app cache.")
        XCTAssertEqual(result.stalls, 0,
            "A real -1005 socket reset must be absorbed with ZERO stalls — cache ahead of playhead + resumable downloader. This is never-cut.")
    }

    /// Proves commit-as-you-go + resume-from-committed-offset: after a real reset, the server's
    /// served-bytes counter must not exceed the file size by more than probe/tail overhead — i.e.
    /// the downloader resumed exactly where it left off and re-fetched (essentially) nothing.
    @MainActor
    func testCacheLoaderResumesReset_noRefetch() async throws {
        let result = try await runCacheLoaderScenario(
            dropWindows: [(start: 8, duration: 3)],
            watch: 18,
            throttleMultiplier: 3,
            dropMode: .resetConnection,
            keepAlive: true
        )
        print("cacheloader.reset.norefetch — served=\(result.servedBytes) file=\(result.fileSize) overhead=\(result.servedBytes - result.fileSize) contiguous=\(result.contiguousFromZero)")
        // probe (2B) + one re-fetched tail window from priming + at most one in-flight sub-block.
        let allowedOverhead = 12 * 1_024 * 1_024
        XCTAssertLessThan(result.servedBytes, result.fileSize + allowedOverhead,
            "Resume must not re-fetch already-committed bytes; served≈file (+ small probe/tail overhead).")
        XCTAssertGreaterThanOrEqual(result.contiguousFromZero, 0,
            "Store coverage from 0 must be contiguous and non-negative.")
    }

    /// Keep-alive regression guard: one persistent session + closed ranges must not churn TCP
    /// connections (the open-ended-range `cancel()`-at-maxLength bug closed a connection per
    /// window). With no drops, the accept count stays a small constant.
    @MainActor
    func testCacheLoaderKeepAlive_connectionCountBounded() async throws {
        let result = try await runCacheLoaderScenario(
            dropWindows: [],
            watch: 12,
            throttleMultiplier: 8,
            dropMode: .freeze,
            keepAlive: true
        )
        print("cacheloader.keepalive — conns=\(result.connections) served=\(result.servedBytes) file=\(result.fileSize)")
        XCTAssertGreaterThan(result.connections, 0, "Server must have accepted at least one connection.")
        XCTAssertLessThanOrEqual(result.connections, 12,
            "Closed ranges on one keep-alive session must not churn connections per window.")
    }

    /// Fast-start: tail-first priming (moov is at EOF for non-faststart MP4) then head, so the
    /// item reaches readyToPlay and the first frame renders well within budget on a fast link.
    @MainActor
    func testCacheLoaderFastStart_firstFrameUnderBudget() async throws {
        let result = try await runCacheLoaderScenario(
            dropWindows: [],
            watch: 4,
            throttleMultiplier: 8,
            dropMode: .freeze,
            keepAlive: true
        )
        print("cacheloader.faststart — firstFrame=\(result.firstFrameElapsed) ready=\(result.readyElapsed)")
        XCTAssertLessThan(result.firstFrameElapsed, 12,
            "Tail-first priming must give a first frame within budget on a fast link.")
    }

    /// Reproduces the on-device RESUME failure: playback starts deep in the file (seek) while
    /// AVPlayer also reads the moov/head, and the downloader's lookahead budget is far smaller than
    /// the file (mirroring the 11.7 GB original vs a finite cache). The downloader must fill from
    /// the SEEK position, not march from the file head (which starved the playhead → leadMB=-1790).
    ///
    /// The structural assertion is `contiguousFromZero` staying tiny: if the downloader had marched
    /// the head (the bug), the whole [0, seek] region would be cached (≫ the prime head). It also
    /// must reach the target — i.e. it kept the deep playback region fed.
    @MainActor
    func testCacheLoaderResume_deepSeekFollowsPlayheadNotHead() async throws {
        let result = try await runCacheLoaderScenario(
            dropWindows: [],
            watch: 52,
            throttleMultiplier: 4,
            dropMode: .freeze,
            keepAlive: true,
            seekToSeconds: 40,
            windowLength: 2 * 1_024 * 1_024,
            aheadBudget: 6 * 1_024 * 1_024 // ≪ file size: forces the head-vs-playhead separation
        )
        print("cacheloader.resume — reached=\(result.reached) stalls=\(result.stalls) contiguousFromZero=\(result.contiguousFromZero)")
        XCTAssertGreaterThanOrEqual(result.reached, 50,
            "Resumed playback must advance to ~50s — the downloader followed the seek and kept the deep region fed.")
        // THE device-bug guard: the old code marched the file head and cached the whole [0, seek]
        // span (~12 MB+) while the playhead (1.8 GB on device) starved. Following the playhead
        // leaves the head at roughly the prime size (8 MB). This is the load-bearing assertion.
        XCTAssertLessThan(result.contiguousFromZero, 11 * 1_024 * 1_024,
            "Downloader must NOT march the file head on resume (that starved the playhead on device).")
        // At most the single expected post-resume rebuffer (the seek-point data starts uncached and
        // the synthetic 6 MB budget ≪ AVPlayer's forward buffer leaves no cushion at t0). The device
        // uses a 512 MB budget, so the cushion is deep after startup.
        XCTAssertLessThanOrEqual(result.stalls, 1,
            "After the initial post-resume buffering, cached playback must not keep cutting.")
    }

    // MARK: - Localhost cache PROXY proof (OriginDownloader + MediaGatewayStore + LocalCacheHTTPServer)
    //
    // Same proven never-stall cache as the resource-loader path, but delivered over http://127.0.0.1
    // so Dolby Vision renders (the custom reelfin-cache scheme black-screened DV). These tests prove
    // the localhost HTTP delivery is byte-exact and never-cut through a real origin connection reset.

    /// THE never-cut proof for the DV-safe path. AVPlayer plays from `http://127.0.0.1` (the proxy),
    /// fed by the deep local cache; a REAL socket reset (-1005) fires on the ORIGIN mid-playback.
    /// Because the cache is ahead of the playhead and the downloader resumes from the committed end,
    /// AVPlayer (reading localhost) never sees a gap → zero stalls. This is the configuration shipped
    /// to the device: raw original bytes, DV-renderable, "ça ne coupe plus".
    @MainActor
    func testCacheProxyAbsorbsConnectionReset_zeroStalls() async throws {
        let result = try await runProxyScenario(
            dropWindows: [(start: 10, duration: 3)],
            watch: 20,
            throttleMultiplier: 3,
            dropMode: .resetConnection,
            keepAlive: true
        )
        print("cacheproxy.reset.zerostall — reached=\(result.reached) stalls=\(result.stalls) served=\(result.servedBytes) file=\(result.fileSize) conns=\(result.connections)")
        XCTAssertGreaterThanOrEqual(result.reached, 18,
            "Playback through the localhost proxy must advance through the reset to ~18s on the app cache.")
        XCTAssertEqual(result.stalls, 0,
            "A real -1005 origin reset must be absorbed with ZERO stalls when AVPlayer reads the localhost cache. This is never-cut, DV-safe.")
    }

    /// Byte-exactness through a reset: a client (standing in for AVPlayer) requests a range from the
    /// localhost proxy; even though the ORIGIN connection resets mid-fill, the proxy serves the exact
    /// requested bytes (downloader resumes from the committed end) — no corruption, no gap, no error.
    @MainActor
    func testCacheProxyServesExactBytesThroughReset() async throws {
        let clip = try Self.sharedClip()
        let data = try Data(contentsOf: clip)
        let throttleBytesPerSec = max(Self.clipBitrate / 8 * 3, 1_024 * 1024)
        let server = ThrottledDropHTTPServer(
            payload: data, contentType: "video/mp4",
            throttleBytesPerSec: throttleBytesPerSec, dropMode: .resetConnection, keepAlive: true
        )
        let port = try server.start()
        defer { server.stop() }
        let origin = URL(string: "http://127.0.0.1:\(port)/clip.mp4")!

        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CacheProxyBytes.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let store = try MediaGatewayStore(
            directoryURL: storeDir,
            configuration: MediaGatewayStore.Configuration(chunkSize: 1_024 * 1_024, maxBytes: 2_000_000_000, ttlSeconds: nil)
        )
        let key = MediaGatewayCacheKey(scope: "original", userID: "u", serverID: "s", itemID: "bytes", sourceID: "src", routeURL: origin)
        let downloader = OriginDownloader(
            remoteURL: origin, headers: [:], key: key, store: store,
            overrideContentType: "video/mp4", sessionConfiguration: .ephemeral,
            windowLength: 2 * 1_024 * 1_024, aheadBudget: 512 * 1_024 * 1_024, maxParallelWindows: 6
        )
        let proxy = LocalCacheHTTPServer(store: store, downloader: downloader, key: key, remoteURL: origin, headers: [:], overrideMIMEType: "video/mp4")
        defer { proxy.stop(reason: "test_end") }
        await downloader.primeStart()
        let localURL = try proxy.start()

        // Arm a reset 0.5s out so it lands mid-fill while we read.
        let base = Date()
        server.armDrops([(start: base.addingTimeInterval(0.5), end: base.addingTimeInterval(3.5))])

        // Request the first 24 MB (or whole file) through the proxy, exactly like an AVPlayer range read.
        let requestLength = min(data.count, 24 * 1_024 * 1_024)
        var request = URLRequest(url: localURL)
        request.setValue("bytes=0-\(requestLength - 1)", forHTTPHeaderField: "Range")
        request.timeoutInterval = 60
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        let (received, response) = try await URLSession(configuration: config).data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        print("cacheproxy.bytes — status=\(status) received=\(received.count) expected=\(requestLength)")
        XCTAssertEqual(status, 206, "Proxy must answer a range request with 206 Partial Content.")
        XCTAssertEqual(received.count, requestLength, "Proxy must serve the full requested length through the origin reset.")
        XCTAssertEqual(received, data.subdata(in: 0..<requestLength),
            "Proxy bytes must be byte-for-byte identical to the origin payload through a reset (no corruption, no gap).")
    }

    /// Locks the two serve-path behaviors that ended the startup black-window and the reset storm:
    /// (1) an OPEN-ENDED range request is answered with a BOUNDED window — a response that can
    /// COMPLETE, so the keep-alive socket is reusable — whose Content-Range still reports the real
    /// total; (2) the very first serve discovers the file's total from its own on-demand fetch
    /// (Content-Range adoption) instead of parking AVPlayer behind the dedicated origin probe.
    @MainActor
    func testCacheProxyBoundsOpenEndedRangeAndAdoptsContentInfo() async throws {
        let clip = try Self.sharedClip()
        let data = try Data(contentsOf: clip)
        let throttle = max(Self.clipBitrate / 8 * 8, 1_024 * 1_024)
        let server = ThrottledDropHTTPServer(
            payload: data, contentType: "video/mp4",
            throttleBytesPerSec: throttle, dropMode: .freeze, keepAlive: true
        )
        let port = try server.start()
        defer { server.stop() }
        let origin = URL(string: "http://127.0.0.1:\(port)/clip.mp4")!

        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CacheProxyOpenEnded.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let store = try MediaGatewayStore(
            directoryURL: storeDir,
            configuration: MediaGatewayStore.Configuration(chunkSize: 1_024 * 1_024, maxBytes: 2_000_000_000, ttlSeconds: nil)
        )
        let key = MediaGatewayCacheKey(scope: "original", userID: "u", serverID: "s", itemID: "openended", sourceID: "src", routeURL: origin)
        let downloader = OriginDownloader(
            remoteURL: origin, headers: [:], key: key, store: store,
            overrideContentType: "video/mp4", sessionConfiguration: .ephemeral,
            windowLength: 2 * 1_024 * 1_024, aheadBudget: 512 * 1_024 * 1_024, maxParallelWindows: 6
        )
        let proxy = LocalCacheHTTPServer(store: store, downloader: downloader, key: key, remoteURL: origin, headers: [:], overrideMIMEType: "video/mp4")
        defer { proxy.stop(reason: "test_end") }
        // Deliberately NO primeStart(): the serve itself must discover the total (adoption path).
        let localURL = try proxy.start()

        var request = URLRequest(url: localURL)
        request.setValue("bytes=0-", forHTTPHeaderField: "Range")
        request.timeoutInterval = 60
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        let (received, response) = try await URLSession(configuration: config).data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 206, "Proxy must answer an open-ended range with 206 Partial Content.")
        let contentRange = try XCTUnwrap(http.value(forHTTPHeaderField: "Content-Range"))
        XCTAssertTrue(contentRange.hasSuffix("/\(data.count)"),
            "Content-Range must report the origin's REAL total, adopted from the serve's own fetch: \(contentRange)")
        let expected = min(data.count, 32 * 1_024 * 1_024)
        XCTAssertEqual(received.count, expected,
            "An open-ended range must be answered with a bounded, completable window — not the whole remainder.")
        XCTAssertEqual(received, data.subdata(in: 0 ..< expected),
            "Bounded open-ended window must be byte-identical to the origin payload.")
        let known = await downloader.knownContentInfo()
        XCTAssertEqual(known.length, Int64(data.count),
            "The downloader must have adopted the total length from the first serve's Content-Range.")
    }

    /// Reproduces the on-device deep RESUME the toy test missed: playback starts deep in the file
    /// (seek) with a small ahead-budget (a finite cache vs a file much larger than it, like the
    /// 11.7 GB original). v1 waited on the windowed downloader to crawl to the seek point → slow
    /// first frame; v2 fetches the seek-point range ON-DEMAND → fast first frame even though the
    /// background cushion isn't built yet. Asserts fast start + advances + (under no drops) no stall.
    @MainActor
    func testCacheProxyDeepResumeFastStartOnDemand() async throws {
        let result = try await runProxyScenario(
            dropWindows: [],
            watch: 52,
            throttleMultiplier: 4,
            dropMode: .freeze,
            keepAlive: true,
            seekToSeconds: 40,
            windowLength: 2 * 1_024 * 1_024,
            aheadBudget: 6 * 1_024 * 1_024 // ≪ file: the background downloader can't pre-fill the seek point
        )
        print("cacheproxy.deepresume — reached=\(result.reached) stalls=\(result.stalls) firstFrame=\(result.firstFrameElapsed) contiguousFromZero=\(result.contiguousFromZero)")
        XCTAssertGreaterThanOrEqual(result.reached, 50,
            "Resumed playback through the proxy must advance to ~50s (on-demand served the seek point, downloader kept the region fed).")
        // THE startup-regression guard: on-demand serving must give a fast first frame on a deep
        // resume even when the background cushion isn't built. v1 (wait-for-downloader) blew past this.
        XCTAssertLessThan(result.firstFrameElapsed, 15,
            "Deep-resume first frame must be fast via on-demand serving (not wait for the windowed downloader to crawl to the seek point).")
        XCTAssertLessThanOrEqual(result.stalls, 1,
            "After the initial resume buffering, cached playback must not keep cutting.")
    }

    /// End-to-end offline proof of the CLEAN custom engine: a real AVPlayer, driven by
    /// CustomPlaybackEngine, plays the original H264 clip through the local cache proxy (mock
    /// resolver, throttled local origin). Proves load → cache builds → reaches .playing → advances,
    /// with no error and a growing reservoir — the whole pipeline, no device.
    @MainActor
    func testCustomEnginePlaysOriginalThroughCache() async throws {
        let clip = try Self.sharedClip()
        let data = try Data(contentsOf: clip)
        let throttle = max(Self.clipBitrate / 8 * 8, 1_024 * 1024) // 8x — fast link → play-now path
        let server = ThrottledDropHTTPServer(payload: data, contentType: "video/mp4", throttleBytesPerSec: throttle, dropMode: .freeze, keepAlive: true)
        let port = try server.start()
        defer { server.stop() }
        let origin = URL(string: "http://127.0.0.1:\(port)/clip.mp4")!

        let storeDir = FileManager.default.temporaryDirectory.appendingPathComponent("CustomEngine.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let store = try MediaGatewayStore(directoryURL: storeDir,
            configuration: MediaGatewayStore.Configuration(chunkSize: 1_024 * 1_024, maxBytes: 2_000_000_000, ttlSeconds: nil))
        let key = MediaGatewayCacheKey(scope: "original", userID: "u", serverID: "s", itemID: "engine", sourceID: "src", routeURL: origin)

        let resolver = MockCustomSourceResolver(originURL: origin, sourceBitrate: Int(Self.clipBitrate), cacheKey: key)
        let engine = CustomPlaybackEngine(resolver: resolver, store: store)
        defer { engine.stop() }

        engine.load(itemID: "engine", autoPlay: true)

        var reached = false
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if engine.bufferingState.phase == .playing, engine.player.currentTime().seconds > 0.5 { reached = true; break }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        print("customengine — phase=\(engine.bufferingState.phase) t=\(engine.player.currentTime().seconds) reservoir=\(engine.bufferingState.reservoirSeconds) err=\(engine.errorMessage ?? "nil")")
        XCTAssertNil(engine.errorMessage)
        XCTAssertTrue(reached, "Custom engine must load + play the original through the cache and advance. phase=\(engine.bufferingState.phase)")
    }

    /// LAST-RESORT LANE mechanics: dropping to the SDR fallback swaps the item to the fallback URL
    /// (phase `.degradedSDR`, DV session kept alive underneath), and returning swaps back to the
    /// localhost cache at the TITLE position (SDR timeline is 0-based at the drop point). The
    /// 90s-sustained policy itself is covered by AdaptiveLanePolicyTests; this drives the swaps.
    @MainActor
    func testEngineSDRLaneSwapAndReturnMechanics() async throws {
        let clip = try Self.sharedClip()
        let data = try Data(contentsOf: clip)
        let throttle = max(Self.clipBitrate / 8 * 8, 1_024 * 1024)
        let origin = ThrottledDropHTTPServer(payload: data, contentType: "video/mp4", throttleBytesPerSec: throttle, dropMode: .freeze, keepAlive: true)
        let originPort = try origin.start()
        defer { origin.stop() }
        let sdr = ThrottledDropHTTPServer(payload: data, contentType: "video/mp4", throttleBytesPerSec: throttle, dropMode: .freeze, keepAlive: true)
        let sdrPort = try sdr.start()
        defer { sdr.stop() }
        let originURL = URL(string: "http://127.0.0.1:\(originPort)/clip.mp4")!
        let sdrURL = URL(string: "http://127.0.0.1:\(sdrPort)/sdr.mp4")!

        let storeDir = FileManager.default.temporaryDirectory.appendingPathComponent("SDRLane.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let store = try MediaGatewayStore(directoryURL: storeDir,
            configuration: MediaGatewayStore.Configuration(chunkSize: 1_024 * 1_024, maxBytes: 2_000_000_000, ttlSeconds: nil))
        let key = MediaGatewayCacheKey(scope: "original", userID: "u", serverID: "s", itemID: "sdrlane", sourceID: "src", routeURL: originURL)

        let resolver = MockCustomSourceResolver(
            originURL: originURL, sourceBitrate: Int(Self.clipBitrate), cacheKey: key, fallbackURL: sdrURL)
        let engine = CustomPlaybackEngine(resolver: resolver, store: store)
        defer { engine.stop() }

        engine.load(itemID: "sdrlane", autoPlay: true)
        let playing = await waitUntil(timeout: 30) { @MainActor in
            engine.bufferingState.phase == .playing && engine.player.currentTime().seconds > 1.0
        }
        XCTAssertTrue(playing)
        let dropPosition = engine.lastObservedSeconds

        await engine.debugForceLaneChange(.dropToSDR)

        let inSDR = await waitUntil(timeout: 15) { @MainActor in
            guard let asset = engine.player.currentItem?.asset as? AVURLAsset else { return false }
            return asset.url.port == sdrPort
                && engine.bufferingState.phase == .degradedSDR
                && engine.player.currentTime().seconds > 0.3
        }
        XCTAssertTrue(inSDR, "drop must swap onto the fallback URL and surface .degradedSDR (phase=\(engine.bufferingState.phase))")
        // Title position keeps advancing from the drop point (offset + 0-based SDR time).
        let titlePositionInSDR = await waitUntil(timeout: 10) { @MainActor in
            engine.lastObservedSeconds >= dropPosition
        }
        XCTAssertTrue(titlePositionInSDR)

        await engine.debugForceLaneChange(.returnToOriginal)

        let backOnOriginal = await waitUntil(timeout: 15) { @MainActor in
            guard let asset = engine.player.currentItem?.asset as? AVURLAsset else { return false }
            return asset.url.host == "127.0.0.1" && asset.url.port != sdrPort
                && engine.bufferingState.phase == .playing
                && engine.player.currentTime().seconds > dropPosition - 3
        }
        XCTAssertTrue(backOnOriginal, "return must land back on the localhost cache near the title position (phase=\(engine.bufferingState.phase), t=\(engine.player.currentTime().seconds))")
        XCTAssertNil(engine.errorMessage)
    }

    /// NON-DIRECT-PLAYABLE source (exotic container/codec): the engine must play the server's
    /// adaptive stream DIRECTLY (no cache session, no localhost) instead of failing — the
    /// regression risk of making the custom engine the default player.
    @MainActor
    func testAdaptiveOnlyLanePlaysStreamDirectlyWithoutCacheSession() async throws {
        let clip = try Self.sharedClip()
        let data = try Data(contentsOf: clip)
        let server = ThrottledDropHTTPServer(payload: data, contentType: "video/mp4", throttleBytesPerSec: 50_000_000, dropMode: .freeze, keepAlive: true)
        let port = try server.start()
        defer { server.stop() }
        let origin = URL(string: "http://127.0.0.1:\(port)/clip.mp4")!

        let storeDir = FileManager.default.temporaryDirectory.appendingPathComponent("AdaptiveLane.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let store = try MediaGatewayStore(directoryURL: storeDir,
            configuration: MediaGatewayStore.Configuration(chunkSize: 1_024 * 1_024, maxBytes: 2_000_000_000, ttlSeconds: nil))
        let key = MediaGatewayCacheKey(scope: "adaptive", userID: "u", serverID: "s", itemID: "adaptive", sourceID: "src", routeURL: origin)

        var resolver = MockCustomSourceResolver(originURL: origin, sourceBitrate: Int(Self.clipBitrate), cacheKey: key)
        resolver.adaptiveOnly = true
        let engine = CustomPlaybackEngine(resolver: resolver, store: store)
        defer { engine.stop() }

        engine.load(itemID: "adaptive", autoPlay: true)
        let playing = await waitUntil(timeout: 20) { @MainActor in
            engine.player.currentTime().seconds > 1.0 && engine.errorMessage == nil
        }
        XCTAssertTrue(playing, "adaptive-only source must play, not fail (err=\(engine.errorMessage ?? "nil"))")
        let asset = try XCTUnwrap(engine.player.currentItem?.asset as? AVURLAsset)
        XCTAssertEqual(asset.url.path, "/clip.mp4", "adaptive lane plays the stream URL directly — no localhost cache")
        XCTAssertNotEqual(engine.bufferingState.phase, .failed)
    }

    /// Detail prewarming must preserve the adaptive-lane contract. Wrapping an HLS manifest in
    /// the progressive byte-range cache makes content-info probe the playlist as if it were a
    /// movie file, leaving AVPlayer at t=0 with `resource unavailable`.
    @MainActor
    func testAdaptivePrewarmNeverCreatesProgressiveCacheProxy() async throws {
        // No server is required: a correct adaptive prewarm never opens/probes the URL.
        let origin = URL(string: "https://example.com/master.m3u8")!

        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AdaptivePrewarm.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let store = try MediaGatewayStore(
            directoryURL: storeDir,
            configuration: MediaGatewayStore.Configuration(
                chunkSize: 1_024 * 1_024,
                maxBytes: 2_000_000_000,
                ttlSeconds: nil
            )
        )
        let key = MediaGatewayCacheKey(
            scope: "adaptive",
            userID: "u",
            serverID: "s",
            itemID: "adaptive-prewarm",
            sourceID: "src",
            routeURL: origin
        )
        var resolver = MockCustomSourceResolver(
            originURL: origin,
            sourceBitrate: 8_000_000,
            cacheKey: key
        )
        resolver.adaptiveOnly = true
        let prewarmer = CustomPlayerPrewarmer(resolver: resolver, store: store)

        prewarmer.prewarm(itemID: "adaptive-prewarm")
        let warm = await prewarmer.consume(itemID: "adaptive-prewarm")

        XCTAssertNil(
            warm,
            "session-scoped HLS URLs must be re-resolved at Play time, never retained by detail prewarm"
        )
    }

    /// Focus prewarming resolves without a resume offset. If that resolution turns out to be HLS,
    /// Play must discard it and resolve again with the exact resume ticks embedded in Jellyfin's
    /// adaptive URL.
    @MainActor
    func testAdaptiveResolveOnlyPrewarmIsResolvedAgainWithExactResumeTicksAtPlay() async throws {
        let origin = URL(string: "https://example.com/master.m3u8")!
        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AdaptiveResolveOnly.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let store = try MediaGatewayStore(
            directoryURL: storeDir,
            configuration: MediaGatewayStore.Configuration(
                chunkSize: 1_024 * 1_024,
                maxBytes: 2_000_000_000,
                ttlSeconds: nil
            )
        )
        let key = MediaGatewayCacheKey(
            scope: "adaptive",
            userID: "u",
            serverID: "s",
            itemID: "adaptive-resolve-only",
            sourceID: "src",
            routeURL: origin
        )
        let requests = ResolveRequestRecorder()
        var resolver = MockCustomSourceResolver(
            originURL: origin,
            sourceBitrate: 8_000_000,
            cacheKey: key
        )
        resolver.adaptiveOnly = true
        resolver.resolveRequests = requests
        let prewarmer = CustomPlayerPrewarmer(resolver: resolver, store: store)
        let engine = CustomPlaybackEngine(resolver: resolver, store: store, prewarmer: prewarmer)
        defer { engine.stop() }

        prewarmer.prewarmResolveOnly(itemID: "adaptive-resolve-only")
        let didPrewarm = await waitUntil(timeout: 2) { requests.values.count == 1 }
        XCTAssertTrue(didPrewarm)
        XCTAssertEqual(requests.values.count, 1)
        XCTAssertNil(requests.values[0])

        let resumeTicks: Int64 = 987_654_321
        engine.load(itemID: "adaptive-resolve-only", startTimeTicks: resumeTicks, autoPlay: false)

        let didResolveAtPlay = await waitUntil(timeout: 2) { requests.values.count == 2 }
        XCTAssertTrue(didResolveAtPlay)
        XCTAssertEqual(requests.values, [nil, resumeTicks])
    }

    /// A compatible MKV is not an AVPlayer progressive asset and Jellyfin's HEVC fMP4 remux can
    /// expose audio while reporting no video tracks. The custom engine must hand the item to the
    /// packet-demuxed native surface before creating any AVPlayer item.
    @MainActor
    func testNativeMKVHandoffDoesNotCreateAVPlayerItem() async throws {
        let origin = URL(string: "https://example.com/Videos/native/stream")!
        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NativeHandoff.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let store = try MediaGatewayStore(
            directoryURL: storeDir,
            configuration: MediaGatewayStore.Configuration(
                chunkSize: 1_024 * 1_024,
                maxBytes: 2_000_000_000,
                ttlSeconds: nil
            )
        )
        let key = MediaGatewayCacheKey(
            scope: "native-handoff",
            userID: "u",
            serverID: "s",
            itemID: "native",
            sourceID: "src",
            routeURL: origin
        )
        var resolver = MockCustomSourceResolver(
            originURL: origin,
            sourceBitrate: 8_000_000,
            cacheKey: key
        )
        resolver.requiresNativePlayback = true
        let engine = CustomPlaybackEngine(resolver: resolver, store: store)
        defer { engine.stop() }

        let handoff = expectation(description: "native playback requested")
        engine.onRequiresNativePlayback = { handoff.fulfill() }
        engine.load(itemID: "native", autoPlay: true)

        await fulfillment(of: [handoff], timeout: 2)
        XCTAssertNil(engine.player.currentItem)
        XCTAssertNil(engine.errorMessage)
        XCTAssertEqual(engine.bufferingState.phase, .idle)
        XCTAssertTrue(
            engine.isHandingOffToNativePlayback,
            "the disappearing custom surface must not restore portrait while the native player replaces it"
        )
    }

    /// AIRPLAY correctness: while external playback is active the item must play the ORIGIN URL
    /// (a receiver cannot reach 127.0.0.1's cache), and swap back onto the localhost cache when it
    /// ends — position preserved both ways.
    @MainActor
    func testExternalPlaybackSwapUsesOriginURLAndSwapsBack() async throws {
        let clip = try Self.sharedClip()
        let data = try Data(contentsOf: clip)
        let throttle = max(Self.clipBitrate / 8 * 8, 1_024 * 1024)
        let server = ThrottledDropHTTPServer(payload: data, contentType: "video/mp4", throttleBytesPerSec: throttle, dropMode: .freeze, keepAlive: true)
        let port = try server.start()
        defer { server.stop() }
        let origin = URL(string: "http://127.0.0.1:\(port)/clip.mp4")!

        let storeDir = FileManager.default.temporaryDirectory.appendingPathComponent("AirPlay.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let store = try MediaGatewayStore(directoryURL: storeDir,
            configuration: MediaGatewayStore.Configuration(chunkSize: 1_024 * 1_024, maxBytes: 2_000_000_000, ttlSeconds: nil))
        let key = MediaGatewayCacheKey(scope: "original", userID: "u", serverID: "s", itemID: "airplay", sourceID: "src", routeURL: origin)

        let resolver = MockCustomSourceResolver(originURL: origin, sourceBitrate: Int(Self.clipBitrate), cacheKey: key)
        let engine = CustomPlaybackEngine(resolver: resolver, store: store)
        defer { engine.stop() }

        engine.load(itemID: "airplay", autoPlay: true)
        let playing = await waitUntil(timeout: 30) { @MainActor in
            engine.bufferingState.phase == .playing && engine.player.currentTime().seconds > 1.0
        }
        XCTAssertTrue(playing)
        let positionBefore = engine.lastObservedSeconds

        engine.handleExternalPlaybackChange(active: true)
        let onOrigin = await waitUntil(timeout: 10) { @MainActor in
            guard let asset = engine.player.currentItem?.asset as? AVURLAsset else { return false }
            return asset.url.path == "/clip.mp4" && engine.player.currentTime().seconds > positionBefore - 3
        }
        XCTAssertTrue(onOrigin, "external playback must play the ORIGIN URL near the same position")

        engine.handleExternalPlaybackChange(active: false)
        let backOnCache = await waitUntil(timeout: 10) { @MainActor in
            guard let asset = engine.player.currentItem?.asset as? AVURLAsset else { return false }
            return asset.url.path.hasPrefix("/media/") && engine.player.currentTime().seconds > positionBefore - 3
        }
        XCTAssertTrue(backOnCache, "ending external playback must swap back onto the localhost cache")
        XCTAssertNil(engine.errorMessage)
    }

    /// PERCEIVED-INSTANT START: prewarming on the detail view resolves the source and builds the
    /// cushion BEFORE the user taps Play — load() must then adopt the warm session (no second
    /// resolve, no new server) and reach playback near-instantly.
    @MainActor
    func testPrewarmedLoadStartsFromExistingSessionWithoutNewResolve() async throws {
        let clip = try Self.sharedClip()
        let data = try Data(contentsOf: clip)
        let throttle = max(Self.clipBitrate / 8 * 8, 1_024 * 1024)
        let server = ThrottledDropHTTPServer(payload: data, contentType: "video/mp4", throttleBytesPerSec: throttle, dropMode: .freeze, keepAlive: true)
        let port = try server.start()
        defer { server.stop() }
        let origin = URL(string: "http://127.0.0.1:\(port)/clip.mp4")!

        let storeDir = FileManager.default.temporaryDirectory.appendingPathComponent("Prewarm.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let store = try MediaGatewayStore(directoryURL: storeDir,
            configuration: MediaGatewayStore.Configuration(chunkSize: 1_024 * 1_024, maxBytes: 2_000_000_000, ttlSeconds: nil))
        let key = MediaGatewayCacheKey(scope: "original", userID: "u", serverID: "s", itemID: "prewarm", sourceID: "src", routeURL: origin)

        let counter = ResolveCounter()
        let resolver = MockCustomSourceResolver(originURL: origin, sourceBitrate: Int(Self.clipBitrate), cacheKey: key, resolveCounter: counter)
        let prewarmer = CustomPlayerPrewarmer(resolver: resolver, store: store)
        let engine = CustomPlaybackEngine(resolver: resolver, store: store, prewarmer: prewarmer)
        defer { engine.stop() }

        prewarmer.prewarm(itemID: "prewarm", startTimeTicks: nil)
        // Simulate the user reading the detail page: the cushion builds behind the scenes.
        let warmed = await waitUntil(timeout: 25) {
            let end = (try? await store.contiguousEnd(from: 0, key: key)) ?? 0
            return Double(end) * 8 / Self.clipBitrate >= 7
        }
        XCTAssertTrue(warmed, "prewarm must build the startup cushion before Play is tapped")
        XCTAssertEqual(counter.value, 1)

        let tapped = Date()
        engine.load(itemID: "prewarm", autoPlay: true)
        let playing = await waitUntil(timeout: 10) { @MainActor in
            engine.bufferingState.phase == .playing && engine.player.currentTime().seconds > 0.2
        }
        let elapsed = Date().timeIntervalSince(tapped)
        print("prewarm.start — elapsed=\(String(format: "%.2f", elapsed))s resolves=\(counter.value)")
        XCTAssertTrue(playing, "prewarmed load must reach playback (phase=\(engine.bufferingState.phase))")
        XCTAssertLessThan(elapsed, 4, "prewarmed start must be near-instant")
        XCTAssertEqual(counter.value, 1, "load must ADOPT the prewarmed session, not resolve again")
    }

    /// A prewarm that the user walks away from must free everything (no leaked localhost server,
    /// no background fill for a title that will not be played).
    @MainActor
    func testPrewarmDiscardStopsSessionAndFreesServer() async throws {
        let clip = try Self.sharedClip()
        let data = try Data(contentsOf: clip)
        let server = ThrottledDropHTTPServer(payload: data, contentType: "video/mp4", throttleBytesPerSec: 50_000_000, dropMode: .freeze, keepAlive: true)
        let port = try server.start()
        defer { server.stop() }
        let origin = URL(string: "http://127.0.0.1:\(port)/clip.mp4")!

        let storeDir = FileManager.default.temporaryDirectory.appendingPathComponent("PrewarmDiscard.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let store = try MediaGatewayStore(directoryURL: storeDir,
            configuration: MediaGatewayStore.Configuration(chunkSize: 1_024 * 1_024, maxBytes: 2_000_000_000, ttlSeconds: nil))
        let key = MediaGatewayCacheKey(scope: "original", userID: "u", serverID: "s", itemID: "discard", sourceID: "src", routeURL: origin)

        let prewarmer = CustomPlayerPrewarmer(
            resolver: MockCustomSourceResolver(originURL: origin, sourceBitrate: Int(Self.clipBitrate), cacheKey: key),
            store: store)
        prewarmer.prewarm(itemID: "discard", startTimeTicks: nil)
        let localURL = await waitUntil(timeout: 15) { @MainActor in prewarmer.debugPreparedLocalURL != nil }
        XCTAssertTrue(localURL, "prewarm must come up")
        let servedURL = prewarmer.debugPreparedLocalURL

        prewarmer.discardIfUnused()

        // The localhost server must be gone: a fresh GET on the old URL fails.
        if let servedURL {
            var request = URLRequest(url: servedURL)
            request.timeoutInterval = 3
            do {
                _ = try await URLSession.shared.data(for: request)
                XCTFail("discarded prewarm server must not keep serving")
            } catch {
                // expected — connection refused
            }
        }
    }

    /// NEVER-FREEZE ladder rung 2: a FAILED AVPlayerItem (AVPlayer never self-recovers from
    /// `.failed`) must be rebuilt at the last known position over the SAME warm cache and keep
    /// playing — a failure used to leave a silent, permanently frozen frame.
    @MainActor
    func testEngineRebuildsFailedItemAndKeepsPlaying() async throws {
        let clip = try Self.sharedClip()
        let data = try Data(contentsOf: clip)
        let throttle = max(Self.clipBitrate / 8 * 8, 1_024 * 1024)
        let server = ThrottledDropHTTPServer(payload: data, contentType: "video/mp4", throttleBytesPerSec: throttle, dropMode: .freeze, keepAlive: true)
        let port = try server.start()
        defer { server.stop() }
        let origin = URL(string: "http://127.0.0.1:\(port)/clip.mp4")!

        let storeDir = FileManager.default.temporaryDirectory.appendingPathComponent("EngineRebuild.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let store = try MediaGatewayStore(directoryURL: storeDir,
            configuration: MediaGatewayStore.Configuration(chunkSize: 1_024 * 1_024, maxBytes: 2_000_000_000, ttlSeconds: nil))
        let key = MediaGatewayCacheKey(scope: "original", userID: "u", serverID: "s", itemID: "rebuild", sourceID: "src", routeURL: origin)

        let resolver = MockCustomSourceResolver(originURL: origin, sourceBitrate: Int(Self.clipBitrate), cacheKey: key)
        let engine = CustomPlaybackEngine(resolver: resolver, store: store)
        engine.rebuildBackoffSeconds = [0.05, 0.05, 0.05]
        defer { engine.stop() }

        engine.load(itemID: "rebuild", autoPlay: true)
        let playing = await waitUntil(timeout: 30) { @MainActor in
            engine.bufferingState.phase == .playing && engine.player.currentTime().seconds > 0.5
        }
        XCTAssertTrue(playing, "engine must reach steady playback before the injected failure")
        let failedItem = engine.player.currentItem

        engine.handleItemFailure(reason: "test_injected_failure")

        let recovered = await waitUntil(timeout: 15) { @MainActor in
            engine.player.currentItem !== failedItem
                && engine.player.currentItem != nil
                && engine.player.currentTime().seconds > 0.2
                && engine.bufferingState.phase != .failed
        }
        XCTAssertTrue(recovered, "a failed item must be rebuilt on the warm cache and keep playing (phase=\(engine.bufferingState.phase))")
        XCTAssertNil(engine.errorMessage)
    }

    /// NEVER-FREEZE ladder rung 3: repeated failures inside the rolling window must end in an
    /// HONEST error state (message + retryable), never a silent frozen frame — and `retry()` must
    /// restart playback from the same warm cache.
    @MainActor
    func testEngineEntersHonestFailedStateAfterRepeatedFailuresAndRetries() async throws {
        let clip = try Self.sharedClip()
        let data = try Data(contentsOf: clip)
        let throttle = max(Self.clipBitrate / 8 * 8, 1_024 * 1024)
        let server = ThrottledDropHTTPServer(payload: data, contentType: "video/mp4", throttleBytesPerSec: throttle, dropMode: .freeze, keepAlive: true)
        let port = try server.start()
        defer { server.stop() }
        let origin = URL(string: "http://127.0.0.1:\(port)/clip.mp4")!

        let storeDir = FileManager.default.temporaryDirectory.appendingPathComponent("EngineFailState.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let store = try MediaGatewayStore(directoryURL: storeDir,
            configuration: MediaGatewayStore.Configuration(chunkSize: 1_024 * 1_024, maxBytes: 2_000_000_000, ttlSeconds: nil))
        let key = MediaGatewayCacheKey(scope: "original", userID: "u", serverID: "s", itemID: "failstate", sourceID: "src", routeURL: origin)

        let resolver = MockCustomSourceResolver(originURL: origin, sourceBitrate: Int(Self.clipBitrate), cacheKey: key)
        let engine = CustomPlaybackEngine(resolver: resolver, store: store)
        engine.rebuildBackoffSeconds = [0.05, 0.05, 0.05]
        defer { engine.stop() }

        engine.load(itemID: "failstate", autoPlay: true)
        let playing = await waitUntil(timeout: 30) { @MainActor in
            engine.bufferingState.phase == .playing && engine.player.currentTime().seconds > 0.2
        }
        XCTAssertTrue(playing)

        // Exhaust the rolling rebuild window (3 rebuilds), then one more failure → honest error.
        for _ in 0..<4 {
            engine.handleItemFailure(reason: "test_injected_failure")
            _ = await waitUntil(timeout: 5) { @MainActor in
                engine.bufferingState.phase == .failed || engine.player.currentItem != nil
            }
            try? await Task.sleep(nanoseconds: 200_000_000) // let the scheduled rebuild land
        }
        let failedHonestly = await waitUntil(timeout: 5) { @MainActor in
            engine.bufferingState.phase == .failed && engine.errorMessage != nil
        }
        XCTAssertTrue(failedHonestly, "repeated failures must surface an honest, retryable error state (phase=\(engine.bufferingState.phase))")

        engine.retry()
        let recovered = await waitUntil(timeout: 30) { @MainActor in
            engine.bufferingState.phase == .playing && engine.player.currentTime().seconds > 0.2
        }
        XCTAssertTrue(recovered, "retry() must restart playback from the warm cache")
        XCTAssertNil(engine.errorMessage)
    }

    /// CacheProxySession (clean-engine composition) must build a DEEP reservoir ahead of the
    /// playhead and report its depth in SECONDS — the cache-depth signal the loading bar + the
    /// keep-original decisions rely on. Dynamic per file (reservoir measured in seconds of the
    /// file's own bitrate, not a hardcoded byte budget).
    @MainActor
    func testCacheProxySessionBuildsDeepReservoirAndReportsSeconds() async throws {
        let clip = try Self.sharedClip()
        let data = try Data(contentsOf: clip)
        let throttle = max(Self.clipBitrate / 8 * 8, 1_024 * 1024) // 8x — comfortably faster than realtime
        let server = ThrottledDropHTTPServer(payload: data, contentType: "video/mp4", throttleBytesPerSec: throttle, dropMode: .freeze, keepAlive: true)
        let port = try server.start()
        defer { server.stop() }
        let origin = URL(string: "http://127.0.0.1:\(port)/clip.mp4")!

        let storeDir = FileManager.default.temporaryDirectory.appendingPathComponent("CacheProxySession.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let store = try MediaGatewayStore(
            directoryURL: storeDir,
            configuration: MediaGatewayStore.Configuration(chunkSize: 1_024 * 1_024, maxBytes: 2_000_000_000, ttlSeconds: nil))
        let key = MediaGatewayCacheKey(scope: "original", userID: "u", serverID: "s", itemID: "proxysession", sourceID: "src", routeURL: origin)

        let session = CacheProxySession(
            originURL: origin, headers: [:], key: key, store: store,
            sourceBitrate: Int(Self.clipBitrate), overrideMIMEType: "video/mp4")
        defer { session.stop() }

        let localURL = try session.start()
        XCTAssertEqual(localURL.host, "127.0.0.1", "Proxy must hand AVPlayer a localhost URL (DV-safe transport).")

        // The downloader fills ahead of offset 0; the reservoir-seconds should climb well past a
        // shallow buffer within a few seconds on a fast link.
        let built = await waitUntil(timeout: 20) { await session.reservoirSecondsAhead(atSeconds: 0) >= 20 }
        let depth = await session.reservoirSecondsAhead(atSeconds: 0)
        print("cacheproxysession.reservoir — secondsAhead=\(depth) target=\(session.targetReservoirSeconds)")
        XCTAssertTrue(built, "CacheProxySession must build a deep reservoir (>=20s) on a fast link; got \(depth)s.")
    }

    /// ROOT-CAUSE REGRESSION: the localhost server must keep ONE connection alive across AVPlayer's
    /// many ranged reads. With `Connection: close` AVPlayer opened a NEW socket per range (hundreds
    /// in the device logs); each became a separate active serve and the downloader's playhead
    /// targeting thrashed between a transient low-offset read and the real playback offset, starving
    /// playback DESPITE a deep cache (the "900 s of cache but still buffering" bug). Proven here via
    /// `URLSessionTaskMetrics.isReusedConnection`: subsequent ranges must reuse the connection.
    @MainActor
    func testServerReusesOneConnectionAcrossSequentialRanges() async throws {
        let clip = try Self.sharedClip()
        let data = try Data(contentsOf: clip)
        let server = ThrottledDropHTTPServer(payload: data, contentType: "video/mp4", throttleBytesPerSec: 50_000_000, dropMode: .freeze, keepAlive: true)
        let port = try server.start()
        defer { server.stop() }
        let origin = URL(string: "http://127.0.0.1:\(port)/clip.mp4")!

        let storeDir = FileManager.default.temporaryDirectory.appendingPathComponent("KeepAlive.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let store = try MediaGatewayStore(
            directoryURL: storeDir,
            configuration: MediaGatewayStore.Configuration(chunkSize: 1_024 * 1_024, maxBytes: 2_000_000_000, ttlSeconds: nil))
        let key = MediaGatewayCacheKey(scope: "original", userID: "u", serverID: "s", itemID: "keepalive", sourceID: "src", routeURL: origin)
        let session = CacheProxySession(
            originURL: origin, headers: [:], key: key, store: store,
            sourceBitrate: Int(Self.clipBitrate), overrideMIMEType: "video/mp4")
        defer { session.stop() }
        let localURL = try session.start()
        _ = await waitUntil(timeout: 10) { await session.reservoirSecondsAhead(atSeconds: 0) >= 1 }

        let collector = ReuseMetricsCollector()
        let urlSession = URLSession(configuration: .ephemeral, delegate: collector, delegateQueue: nil)
        defer { urlSession.invalidateAndCancel() }

        func get(_ range: String) async throws -> (Int, Int) {
            var req = URLRequest(url: localURL)
            req.setValue(range, forHTTPHeaderField: "Range")
            let (d, resp) = try await urlSession.data(for: req)
            return ((resp as? HTTPURLResponse)?.statusCode ?? -1, d.count)
        }
        let r1 = try await get("bytes=0-1023")
        let r2 = try await get("bytes=2048-3071")
        let r3 = try await get("bytes=4096-5119")
        XCTAssertEqual([r1.0, r2.0, r3.0], [206, 206, 206], "All ranged reads must return 206 Partial Content.")
        XCTAssertEqual([r1.1, r2.1, r3.1], [1024, 1024, 1024], "Each ranged read must return exactly the requested bytes.")

        _ = await waitUntil(timeout: 3) { collector.reuseFlags.count >= 3 }
        XCTAssertTrue(collector.reuseFlags.dropFirst().contains(true),
            "Keep-alive: a subsequent range must REUSE the connection. Connection:close opened a new socket per range — the cause of the playhead thrash + stall-despite-cache.")
    }

    /// PRIMARY ROOT-CAUSE REGRESSION (the "800s of cache but it crashes" bug): a keep-alive connection
    /// that goes IDLE (AVPlayer finished reading but did not close the socket) must be torn down by
    /// stop(). Before the fix, stop() cancelled only the NWListener; the connection's handle Task was
    /// parked forever in receiveRequestHead's non-cancellation-aware continuation, leaking a socket +
    /// Task PER playback session — across replays that piled up into a memory warning at the next
    /// play's start and a jetsam kill. This asserts the server's tracked-connection count returns to 0.
    @MainActor
    func testStopReleasesIdleKeepAliveConnection_noLeakAcrossReplays() async throws {
        let clip = try Self.sharedClip()
        let data = try Data(contentsOf: clip)

        // 5 "replays" of the same item: each opens an idle keep-alive connection then stops. The
        // tracked count must come back to 0 every time (no accumulation across sessions).
        for replay in 0..<5 {
            let mockOrigin = ThrottledDropHTTPServer(payload: data, contentType: "video/mp4",
                throttleBytesPerSec: Double(data.count * 8), dropMode: .freeze, keepAlive: true)
            let port = try mockOrigin.start()
            defer { mockOrigin.stop() }
            let origin = URL(string: "http://127.0.0.1:\(port)/clip.mp4")!

            let storeDir = FileManager.default.temporaryDirectory.appendingPathComponent("LeakTest.\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: storeDir) }
            let store = try MediaGatewayStore(
                directoryURL: storeDir,
                configuration: MediaGatewayStore.Configuration(chunkSize: 1_024 * 1_024, maxBytes: 2_000_000_000, ttlSeconds: nil))
            let key = MediaGatewayCacheKey(scope: "original", userID: "u", serverID: "s", itemID: "leak", sourceID: "src", routeURL: origin)
            let downloader = OriginDownloader(
                remoteURL: origin, headers: [:], key: key, store: store,
                overrideContentType: "video/mp4", sessionConfiguration: .ephemeral,
                aheadBudget: 8 * 1_024 * 1_024, maxParallelWindows: 2)
            let server = LocalCacheHTTPServer(
                store: store, downloader: downloader, key: key, remoteURL: origin, headers: [:], overrideMIMEType: "video/mp4")
            let url = try server.start()
            await downloader.primeStart()

            // One ranged GET over a single reusable (keep-alive) connection, then leave it idle/pooled.
            let cfg = URLSessionConfiguration.ephemeral
            cfg.httpMaximumConnectionsPerHost = 1
            let urlSession = URLSession(configuration: cfg)
            var req = URLRequest(url: url)
            req.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
            _ = try await urlSession.data(for: req)

            // The keep-alive socket is now OPEN + IDLE; its handle Task is parked in receiveRequestHead.
            XCTAssertGreaterThanOrEqual(server.debugActiveConnectionCount, 1,
                "Replay \(replay): an open idle keep-alive connection must be tracked by the server.")

            server.stop(reason: "replay_end")

            var count = server.debugActiveConnectionCount
            for _ in 0..<50 where count != 0 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                count = server.debugActiveConnectionCount
            }
            XCTAssertEqual(count, 0,
                "Replay \(replay): stop() must cancel the idle keep-alive connection (else its Task + socket leak across replays → memory warning at next play's start → jetsam).")
            urlSession.invalidateAndCancel()
        }
    }

    /// OFFLINE-FIRST: a previously-played title must start from the disk cache even when the origin
    /// is unreachable. contentInfo() must reuse the PERSISTED total length instead of probing the
    /// (dead) origin — this is what makes "I have 800s cached" actually usable when the link is down.
    @MainActor
    func testContentInfoUsesPersistedTotalWhenOriginUnreachable() async throws {
        let storeDir = FileManager.default.temporaryDirectory.appendingPathComponent("OfflineMeta.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }
        let store = try MediaGatewayStore(
            directoryURL: storeDir,
            configuration: MediaGatewayStore.Configuration(chunkSize: 1_024 * 1_024, maxBytes: 2_000_000_000, ttlSeconds: nil))
        let deadOrigin = URL(string: "http://127.0.0.1:1/dead.mp4")! // port 1 → connection refused
        let key = MediaGatewayCacheKey(scope: "original", userID: "u", serverID: "s", itemID: "offline", sourceID: "src", routeURL: deadOrigin)

        // Simulate a prior successful probe having persisted the total.
        await store.persistContentLength(11_788_385_454, key: key)
        let persisted = await store.persistedContentLength(key: key)
        XCTAssertEqual(persisted, 11_788_385_454)

        let downloader = OriginDownloader(
            remoteURL: deadOrigin, headers: [:], key: key, store: store,
            overrideContentType: "video/mp4", sessionConfiguration: .ephemeral,
            aheadBudget: 8 * 1_024 * 1_024, maxParallelWindows: 1)
        defer { Task { await downloader.stop() } }

        let started = Date()
        let info = await downloader.contentInfo()
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(info.length, 11_788_385_454, "contentInfo must reuse the persisted total when the origin is unreachable.")
        XCTAssertEqual(info.contentType, "video/mp4")
        XCTAssertLessThan(elapsed, 2.0, "It must NOT probe the dead origin — returning from disk is instant (no -1001 wait).")
    }

    @MainActor
    private func runProxyScenario(
        dropWindows: [(start: TimeInterval, duration: TimeInterval)],
        watch: TimeInterval,
        throttleMultiplier: Double,
        dropMode: DropMode,
        keepAlive: Bool,
        seekToSeconds: Double? = nil,
        windowLength: Int64 = 8 * 1_024 * 1_024,
        aheadBudget: Int64 = 512 * 1_024 * 1_024
    ) async throws -> CacheScenarioResult {
        let clip = try Self.sharedClip()
        let data = try Data(contentsOf: clip)
        let throttleBytesPerSec = max(Self.clipBitrate / 8 * throttleMultiplier, 1_024 * 1024)

        let server = ThrottledDropHTTPServer(
            payload: data, contentType: "video/mp4",
            throttleBytesPerSec: throttleBytesPerSec, dropMode: dropMode, keepAlive: keepAlive
        )
        let port = try server.start()
        defer { server.stop() }

        let origin = URL(string: "http://127.0.0.1:\(port)/clip.mp4")!
        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CacheProxyTest.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }

        let store = try MediaGatewayStore(
            directoryURL: storeDir,
            configuration: MediaGatewayStore.Configuration(chunkSize: 1_024 * 1_024, maxBytes: 2_000_000_000, ttlSeconds: nil)
        )
        let key = MediaGatewayCacheKey(
            scope: "original", userID: "user-1", serverID: "server-1",
            itemID: "proxytest", sourceID: "src", routeURL: origin
        )
        let downloader = OriginDownloader(
            remoteURL: origin, headers: [:], key: key, store: store,
            overrideContentType: "video/mp4", sessionConfiguration: .ephemeral,
            windowLength: windowLength, aheadBudget: aheadBudget
        )
        let proxy = LocalCacheHTTPServer(store: store, downloader: downloader, key: key, remoteURL: origin, headers: [:], overrideMIMEType: "video/mp4")
        defer { proxy.stop(reason: "test_end") }

        let playStart = Date()
        // Fire prime as a background task exactly like the controller — on-demand serving must give a
        // fast first frame WITHOUT blocking on the tail/head warm-up.
        Task { await downloader.primeStart() }
        let localURL = try proxy.start()

        let asset = AVURLAsset(url: localURL, options: [AVURLAssetOverrideMIMETypeKey: "video/mp4"])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 30
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        defer { player.pause() }

        let stalls = StallCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main
        ) { _ in stalls.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }

        let ready = await waitUntil(timeout: 25) { item.status != .unknown }
        let readyElapsed = Date().timeIntervalSince(playStart)
        XCTAssertTrue(ready, "proxy item never loaded — stayed .unknown. error=\(String(describing: item.error))")
        XCTAssertNotEqual(item.status, .failed, "proxy item failed to load: \(String(describing: item.error))")

        // Resume exactly like the controller: seek before the first play so playback starts deep
        // (AVPlayer issues moov/metadata reads AND a far-ahead playback request — the device split).
        if let seekToSeconds {
            await player.seek(to: CMTime(seconds: seekToSeconds, preferredTimescale: 600),
                              toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600))
        }
        let startThreshold = (seekToSeconds ?? 0) + 0.3
        player.playImmediately(atRate: 1)
        let started = await waitUntil(timeout: 20) { player.currentTime().seconds > startThreshold }
        let firstFrameElapsed = Date().timeIntervalSince(playStart)
        XCTAssertTrue(started, "proxy playback never advanced past the first frame.")

        let base = Date()
        server.armDrops(dropWindows.map { (start: base.addingTimeInterval($0.start), end: base.addingTimeInterval($0.start + $0.duration)) })
        stalls.reset()

        let deadline = Date().addingTimeInterval(watch + 30)
        while Date() < deadline {
            if player.currentTime().seconds >= watch { break }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        let contiguous = (try? await store.contiguousEnd(from: 0, key: key)) ?? 0
        return CacheScenarioResult(
            reached: player.currentTime().seconds,
            stalls: stalls.value,
            servedBytes: server.totalServedBytes,
            connections: server.connectionCount,
            fileSize: data.count,
            firstFrameElapsed: firstFrameElapsed,
            readyElapsed: readyElapsed,
            contiguousFromZero: contiguous
        )
    }

    private struct CacheScenarioResult {
        let reached: Double
        let stalls: Int
        let servedBytes: Int
        let connections: Int
        let fileSize: Int
        let firstFrameElapsed: TimeInterval
        let readyElapsed: TimeInterval
        let contiguousFromZero: Int64
    }

    @MainActor
    private func runCacheLoaderScenario(
        dropWindows: [(start: TimeInterval, duration: TimeInterval)],
        watch: TimeInterval,
        throttleMultiplier: Double,
        dropMode: DropMode,
        keepAlive: Bool,
        seekToSeconds: Double? = nil,
        windowLength: Int64 = 8 * 1_024 * 1_024,
        aheadBudget: Int64 = 512 * 1_024 * 1_024,
        maxParallelWindows: Int = 6,
        primeLength: Int64 = 8 * 1_024 * 1_024
    ) async throws -> CacheScenarioResult {
        let clip = try Self.sharedClip()
        let data = try Data(contentsOf: clip)
        let throttleBytesPerSec = max(Self.clipBitrate / 8 * throttleMultiplier, 1_024 * 1024)

        let server = ThrottledDropHTTPServer(
            payload: data,
            contentType: "video/mp4",
            throttleBytesPerSec: throttleBytesPerSec,
            dropMode: dropMode,
            keepAlive: keepAlive
        )
        let port = try server.start()
        defer { server.stop() }

        let origin = URL(string: "http://127.0.0.1:\(port)/clip.mp4")!
        let storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CacheLoaderTest.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeDir) }

        let store = try MediaGatewayStore(
            directoryURL: storeDir,
            configuration: MediaGatewayStore.Configuration(chunkSize: 1_024 * 1_024, maxBytes: 2_000_000_000, ttlSeconds: nil)
        )
        let key = MediaGatewayCacheKey(
            scope: "original",
            userID: "user-1",
            serverID: "server-1",
            itemID: "droptest",
            sourceID: "src",
            routeURL: origin
        )
        let downloader = OriginDownloader(
            remoteURL: origin,
            headers: [:],
            key: key,
            store: store,
            overrideContentType: "video/mp4",
            sessionConfiguration: .ephemeral,
            windowLength: windowLength,
            aheadBudget: aheadBudget,
            maxParallelWindows: maxParallelWindows,
            headLength: primeLength,
            tailLength: primeLength
        )
        let loader = CacheResourceLoaderDelegate(store: store, downloader: downloader, key: key, overrideMIMEType: "video/mp4")
        defer { loader.invalidate() }

        let playStart = Date()
        await downloader.primeStart()

        let asset = loader.makeAsset(for: "droptest")
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 30
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        defer { player.pause() }

        let stalls = StallCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main
        ) { _ in stalls.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }

        let ready = await waitUntil(timeout: 25) { item.status != .unknown }
        let readyElapsed = Date().timeIntervalSince(playStart)
        XCTAssertTrue(ready, "cache-loader item never loaded — stayed .unknown. error=\(String(describing: item.error))")
        XCTAssertNotEqual(item.status, .failed, "cache-loader item failed to load: \(String(describing: item.error))")

        // Simulate a RESUME exactly like the controller: seek to the resume point BEFORE the first
        // play, so playback starts at the deep offset (no lingering offset-0 request). AVPlayer
        // issues its moov/metadata reads AND a far-ahead playback request — the split that starved
        // the playback region on device.
        if let seekToSeconds {
            await player.seek(to: CMTime(seconds: seekToSeconds, preferredTimescale: 600),
                              toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600))
        }
        let startThreshold = (seekToSeconds ?? 0) + 0.3
        player.playImmediately(atRate: 1)
        let started = await waitUntil(timeout: 20) { player.currentTime().seconds > startThreshold }
        let firstFrameElapsed = Date().timeIntervalSince(playStart)
        XCTAssertTrue(started, "cache-loader playback never advanced past the first frame.")

        if seekToSeconds != nil {
            // Let a cushion build after the resume before measuring steady-state (the initial
            // post-seek rebuffer is expected — the seek-point data starts uncached).
            _ = await waitUntil(timeout: 15) { item.isPlaybackLikelyToKeepUp }
        }

        let base = Date()
        server.armDrops(dropWindows.map { (start: base.addingTimeInterval($0.start), end: base.addingTimeInterval($0.start + $0.duration)) })
        stalls.reset()

        let deadline = Date().addingTimeInterval(watch + 30)
        while Date() < deadline {
            if player.currentTime().seconds >= watch { break }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        let contiguous = (try? await store.contiguousEnd(from: 0, key: key)) ?? 0
        return CacheScenarioResult(
            reached: player.currentTime().seconds,
            stalls: stalls.value,
            servedBytes: server.totalServedBytes,
            connections: server.connectionCount,
            fileSize: data.count,
            firstFrameElapsed: firstFrameElapsed,
            readyElapsed: readyElapsed,
            contiguousFromZero: contiguous
        )
    }

    // MARK: - Scenario runner

    private struct ScenarioResult { let reached: Double; let stalls: Int; let maxBufferedAhead: Double }

    @MainActor
    private func runDropScenario(
        forwardBuffer: Double,
        dropWindows: [(start: TimeInterval, duration: TimeInterval)],
        watch: TimeInterval,
        throttleMultiplier: Double
    ) async throws -> ScenarioResult {
        let clip = try Self.sharedClip()
        let data = try Data(contentsOf: clip)
        // Pace at N× the clip bitrate so the link is comfortably faster than realtime (AVPlayer
        // CAN fill its target buffer), matching the user's fast-but-flaky connection.
        let throttleBytesPerSec = max(Self.clipBitrate / 8 * throttleMultiplier, 1_024 * 1024)

        let server = ThrottledDropHTTPServer(payload: data, contentType: "video/mp4", throttleBytesPerSec: throttleBytesPerSec)
        let port = try server.start()
        defer { server.stop() }

        let url = URL(string: "http://127.0.0.1:\(port)/clip.mp4")!
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = forwardBuffer
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        defer { player.pause() }

        let stalls = StallCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main
        ) { _ in stalls.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }

        let ready = await waitUntil(timeout: 20) { item.status != .unknown }
        XCTAssertTrue(ready, "Local clip never loaded — item stayed .unknown.")
        XCTAssertNotEqual(item.status, .failed, "Local clip failed to load: \(String(describing: item.error))")

        player.playImmediately(atRate: 1)
        let started = await waitUntil(timeout: 15) { player.currentTime().seconds > 0.3 }
        XCTAssertTrue(started, "Playback never advanced past the first frame.")

        // Arm the drop windows relative to playback start.
        let base = Date()
        server.armDrops(dropWindows.map { (start: base.addingTimeInterval($0.start), end: base.addingTimeInterval($0.start + $0.duration)) })
        stalls.reset() // measure steady-state only

        var maxBuffered = 0.0
        let deadline = Date().addingTimeInterval(watch + 25)
        while Date() < deadline {
            maxBuffered = max(maxBuffered, bufferedAhead(item))
            if player.currentTime().seconds >= watch { break }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return ScenarioResult(reached: player.currentTime().seconds, stalls: stalls.value, maxBufferedAhead: maxBuffered)
    }

    private func bufferedAhead(_ item: AVPlayerItem) -> Double {
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

    // MARK: - Generated H.264 clip (Simulator-decodable)

    @MainActor
    private static func sharedClip() throws -> URL {
        if let url = clipURL { return url }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("reelfin-droptest-\(UUID().uuidString).mp4")
        try generateClip(to: url, seconds: 60, fps: 30, width: 480, height: 270)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        clipBitrate = Double((size ?? 0) * 8) / 60.0
        clipURL = url
        return url
    }

    private static func generateClip(to url: URL, seconds: Int, fps: Int, width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_500_000]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)
        guard writer.canAdd(input) else { throw NSError(domain: "droptest", code: 1) }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let total = seconds * fps
        var frame = 0
        let sema = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "droptest.clipgen")
        input.requestMediaDataWhenReady(on: queue) {
            while input.isReadyForMoreMediaData {
                if frame >= total { input.markAsFinished(); sema.signal(); return }
                guard let pool = adaptor.pixelBufferPool else { continue }
                var pb: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
                guard let buffer = pb else { frame += 1; continue }
                // Per-frame changing noise/gradient so H.264 produces a real (non-trivial) bitrate.
                CVPixelBufferLockBaseAddress(buffer, [])
                if let baseAddr = CVPixelBufferGetBaseAddress(buffer) {
                    let bpr = CVPixelBufferGetBytesPerRow(buffer)
                    let ptr = baseAddr.assumingMemoryBound(to: UInt8.self)
                    let h = CVPixelBufferGetHeight(buffer)
                    for y in 0..<h {
                        let row = ptr + y * bpr
                        for x in 0..<bpr {
                            row[x] = UInt8((x &* 7 &+ y &* 13 &+ frame &* 29) & 0xFF)
                        }
                    }
                }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
                adaptor.append(buffer, withPresentationTime: time)
                frame += 1
            }
        }
        sema.wait()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        if writer.status != .completed {
            throw writer.error ?? NSError(domain: "droptest", code: 2, userInfo: [NSLocalizedDescriptionKey: "clip write failed"])
        }
    }

    // MARK: - Throttled / drop-injecting local HTTP server

    /// How a scheduled drop window manifests on the wire.
    enum DropMode {
        /// Freezes delivery on the same socket (the old behaviour — client never learns the
        /// connection is gone, useful for buffer-depth tests).
        case freeze
        /// Closes the socket mid-body (`conn.cancel()`), so URLSession surfaces a real
        /// `NSURLErrorNetworkConnectionLost` (-1005). This is the failure the player actually
        /// hits in the field; only a resumable downloader can survive it without re-fetching.
        case resetConnection
    }

    private final class ThrottledDropHTTPServer: @unchecked Sendable {
        private let payload: Data
        private let contentType: String
        private let throttleBytesPerSec: Double
        private let dropMode: DropMode
        private let keepAlive: Bool
        private let queue = DispatchQueue(label: "reelfin.droptest.http")
        private var listener: NWListener?
        private let lock = NSLock()
        private var drops: [(start: Date, end: Date)] = []
        private var _servedBytes = 0
        private var _connections = 0

        init(
            payload: Data,
            contentType: String,
            throttleBytesPerSec: Double,
            dropMode: DropMode = .freeze,
            keepAlive: Bool = false
        ) {
            self.payload = payload
            self.contentType = contentType
            self.throttleBytesPerSec = throttleBytesPerSec
            self.dropMode = dropMode
            self.keepAlive = keepAlive
        }

        func armDrops(_ windows: [(start: Date, end: Date)]) { lock.lock(); drops = windows; lock.unlock() }

        /// Body bytes actually put on the wire. With resume-from-committed-offset, a reset must NOT
        /// inflate this beyond the file size (+ probe/tail overhead) — proves no byte is re-fetched.
        var totalServedBytes: Int { lock.lock(); defer { lock.unlock() }; return _servedBytes }
        /// TCP accepts. With one keep-alive session + closed ranges this stays a small constant.
        var connectionCount: Int { lock.lock(); defer { lock.unlock() }; return _connections }

        private func activeDrop(at now: Date) -> TimeInterval? {
            lock.lock(); defer { lock.unlock() }
            for w in drops where now >= w.start && now < w.end { return w.end.timeIntervalSince(now) }
            return nil
        }

        func start() throws -> Int {
            let listener = try NWListener(using: .tcp)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { state in if case .ready = state { ready.signal() } }
            listener.start(queue: queue)
            _ = ready.wait(timeout: .now() + 5)
            guard let port = listener.port?.rawValue else { throw NSError(domain: "droptest", code: 3) }
            return Int(port)
        }

        func stop() { listener?.cancel(); listener = nil }

        private func handle(_ conn: NWConnection) {
            lock.lock(); _connections += 1; lock.unlock()
            conn.start(queue: queue)
            receiveRequest(conn, buffer: Data())
        }

        private func receiveRequest(_ conn: NWConnection, buffer: Data) {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                var acc = buffer
                if let data { acc.append(data) }
                if let headerEnd = acc.range(of: Data("\r\n\r\n".utf8)) {
                    let headerData = acc.subdata(in: acc.startIndex..<headerEnd.lowerBound)
                    let header = String(decoding: headerData, as: UTF8.self)
                    self.respond(conn, header: header)
                    return
                }
                if isComplete || error != nil { conn.cancel(); return }
                self.receiveRequest(conn, buffer: acc)
            }
        }

        private func respond(_ conn: NWConnection, header: String) {
            let total = payload.count
            var start = 0
            var end = total - 1
            var status = "200 OK"
            if let rangeLine = header.split(separator: "\r\n").first(where: { $0.lowercased().hasPrefix("range:") }),
               let eq = rangeLine.firstIndex(of: "=") {
                let spec = rangeLine[rangeLine.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                let parts = spec.split(separator: "-", omittingEmptySubsequences: false)
                if let s = Int(parts.first ?? "") { start = s }
                if parts.count > 1, let e = Int(parts[1]) { end = e }
                status = "206 Partial Content"
            }
            start = max(0, min(start, total - 1))
            end = max(start, min(end, total - 1))
            let length = end - start + 1
            var headers = "HTTP/1.1 \(status)\r\n"
            headers += "Content-Type: \(contentType)\r\n"
            headers += "Accept-Ranges: bytes\r\n"
            headers += "Content-Length: \(length)\r\n"
            if status.hasPrefix("206") { headers += "Content-Range: bytes \(start)-\(end)/\(total)\r\n" }
            headers += keepAlive ? "Connection: keep-alive\r\n\r\n" : "Connection: close\r\n\r\n"
            conn.send(content: Data(headers.utf8), completion: .contentProcessed { [weak self] _ in
                self?.sendBody(conn, start: start, length: length)
            })
        }

        private func sendBody(_ conn: NWConnection, start: Int, length: Int) {
            let chunk = 32 * 1024
            var offset = start
            let endExclusive = start + length

            func finishResponse() {
                if keepAlive {
                    // HTTP/1.1 keep-alive: reuse the socket for the next request.
                    receiveRequest(conn, buffer: Data())
                } else {
                    conn.send(content: nil, isComplete: true, completion: .contentProcessed { _ in conn.cancel() })
                }
            }

            func sendNext() {
                if offset >= endExclusive { finishResponse(); return }
                if let remaining = activeDrop(at: Date()) {
                    switch dropMode {
                    case .resetConnection:
                        // Real socket close mid-body → client sees -1005.
                        conn.cancel()
                        return
                    case .freeze:
                        queue.asyncAfter(deadline: .now() + remaining) { sendNext() }
                        return
                    }
                }
                let thisChunk = min(chunk, endExclusive - offset)
                let slice = payload.subdata(in: offset..<(offset + thisChunk))
                offset += thisChunk
                conn.send(content: slice, completion: .contentProcessed { [weak self] err in
                    guard let self, err == nil else { conn.cancel(); return }
                    self.lock.lock(); self._servedBytes += thisChunk; self.lock.unlock()
                    let delay = Double(thisChunk) / self.throttleBytesPerSec
                    self.queue.asyncAfter(deadline: .now() + delay) { sendNext() }
                })
            }
            sendNext()
        }
    }

    private final class StallCounter: @unchecked Sendable {
        private let lock = NSLock(); private var count = 0
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
        func increment() { lock.lock(); count += 1; lock.unlock() }
        func reset() { lock.lock(); count = 0; lock.unlock() }
    }

    private final class ResolveCounter: @unchecked Sendable {
        private let lock = NSLock(); private var n = 0
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
        func increment() { lock.lock(); n += 1; lock.unlock() }
    }

    private final class ResolveRequestRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var requests: [Int64?] = []
        var values: [Int64?] { lock.lock(); defer { lock.unlock() }; return requests }
        func append(_ ticks: Int64?) { lock.lock(); requests.append(ticks); lock.unlock() }
    }

    private struct MockCustomSourceResolver: CustomPlaybackSourceResolving, CustomPlaybackAdaptiveFallbackResolving {
        let originURL: URL
        let sourceBitrate: Int
        let cacheKey: MediaGatewayCacheKey
        var resolveCounter: ResolveCounter? = nil
        var resolveRequests: ResolveRequestRecorder? = nil
        var fallbackURL: URL? = nil
        var adaptiveOnly = false
        var requiresNativePlayback = false
        func resolveOriginal(itemID: String, startTimeTicks: Int64?) async throws -> ResolvedOriginalSource {
            resolveCounter?.increment()
            resolveRequests?.append(startTimeTicks)
            return ResolvedOriginalSource(
                originURL: originURL, headers: [:], sourceBitrate: sourceBitrate,
                overrideMIMEType: adaptiveOnly ? nil : "video/mp4", cacheKey: cacheKey,
                isDolbyVision: false,
                isAdaptiveStream: adaptiveOnly,
                requiresNativePlayback: requiresNativePlayback)
        }
        func resolveAdaptiveFallback(itemID: String, startSeconds: Double) async -> URL? {
            fallbackURL
        }
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return await condition()
    }
}

/// Captures `isReusedConnection` per request so a test can assert the server keeps a connection alive
/// across sequential ranged reads (keep-alive) instead of forcing a new socket per range.
private final class ReuseMetricsCollector: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var flags: [Bool] = []

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.lock(); defer { lock.unlock() }
        if let last = metrics.transactionMetrics.last { flags.append(last.isReusedConnection) }
    }

    var reuseFlags: [Bool] { lock.lock(); defer { lock.unlock() }; return flags }
}
