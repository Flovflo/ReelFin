@testable import PlaybackEngine
import AVFoundation
import Foundation
import XCTest

final class NativeBridgeLiveURLTests: XCTestCase {
    func testLiveMKVURLBuildsSyntheticHLSSession() async throws {
        guard let sourceURL = resolveLiveURL() else {
            throw XCTSkip("Set REELFIN_NATIVEBRIDGE_LIVE_URL to run live NativeBridge smoke test.")
        }

        let env = ProcessInfo.processInfo.environment
        var headers: [String: String] = [:]
        if let token = env["REELFIN_NATIVEBRIDGE_LIVE_TOKEN"], !token.isEmpty {
            headers["X-Emby-Token"] = token
            headers["Authorization"] = "MediaBrowser Token=\"\(token)\""
        }

        let plan = NativeBridgePlan(
            itemID: "live-item",
            sourceID: "live-source",
            sourceURL: sourceURL,
            videoTrack: TrackInfo(id: 1, trackType: .video, codecID: "V_MPEGH/ISO/HEVC", codecName: "hevc", isDefault: true),
            audioTrack: TrackInfo(id: 2, trackType: .audio, codecID: "A_EAC3", codecName: "eac3", isDefault: true),
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "DOVIWithHDR10",
            dvProfile: 8,
            dvLevel: 6,
            dvBlSignalCompatibilityId: 1,
            whyChosen: "live-smoke"
        )

        let reader = HTTPRangeReader(
            url: sourceURL,
            headers: headers,
            config: .init(
                chunkSize: 64 * 1024,
                maxCacheSize: 24 * 1024 * 1024,
                maxRetries: 4,
                baseRetryDelayMs: 150,
                timeoutInterval: 20,
                maxConcurrentRequests: 2,
                readAheadChunks: 0
            )
        )
        let demuxer = MatroskaDemuxer(reader: reader, plan: plan)
        let repackager = FMP4Repackager(plan: plan)
        let session = SyntheticHLSSession(plan: plan, demuxer: demuxer, repackager: repackager)

        let start = Date()
        try await session.prepare()
        let prepareMs = Date().timeIntervalSince(start) * 1000

        let master = try await session.masterPlaylist()
        let media = try await session.mediaPlaylist(preloadCount: 1)
        let initSegment = try await session.initSegment()
        let segment0 = try await session.segment(sequence: 0)

        XCTAssertTrue(master.contains("#EXTM3U"))
        XCTAssertTrue(media.contains("#EXT-X-MAP"))
        XCTAssertTrue(
            media.contains("#EXT-X-PLAYLIST-TYPE:EVENT") || media.contains("#EXT-X-PLAYLIST-TYPE:VOD"),
            "Media playlist must declare EVENT or VOD type."
        )
        XCTAssertFalse(initSegment.isEmpty)
        XCTAssertFalse(segment0.isEmpty)

        let initBoxes = try BMFFSanityParser.parseTopLevel(initSegment)
        XCTAssertTrue(BMFFSanityParser.containsPath(["ftyp"], in: initBoxes))
        XCTAssertTrue(BMFFSanityParser.containsPath(["moov"], in: initBoxes))

        let fragmentBoxes = try BMFFSanityParser.parseTopLevel(segment0)
        XCTAssertTrue(BMFFSanityParser.containsPath(["moof"], in: fragmentBoxes))
        XCTAssertTrue(BMFFSanityParser.containsPath(["mdat"], in: fragmentBoxes))

        // Guardrail to catch regressions where prepare hangs for too long.
        XCTAssertLessThan(prepareMs, 45_000, "Synthetic HLS prepare is too slow (\(prepareMs)ms)")
    }

    func testLiveMKVLocalHLSServerAndAVPlayerStartup() async throws {
        guard let sourceURL = resolveLiveURL() else {
            throw XCTSkip("Set REELFIN_NATIVEBRIDGE_LIVE_URL to run live NativeBridge smoke test.")
        }

        let env = ProcessInfo.processInfo.environment
        var headers: [String: String] = [:]
        if let token = env["REELFIN_NATIVEBRIDGE_LIVE_TOKEN"], !token.isEmpty {
            headers["X-Emby-Token"] = token
            headers["Authorization"] = "MediaBrowser Token=\"\(token)\""
        }

        let plan = NativeBridgePlan(
            itemID: "live-item-player",
            sourceID: "live-source-player",
            sourceURL: sourceURL,
            videoTrack: TrackInfo(id: 1, trackType: .video, codecID: "V_MPEGH/ISO/HEVC", codecName: "hevc", isDefault: true),
            audioTrack: TrackInfo(id: 2, trackType: .audio, codecID: "A_EAC3", codecName: "eac3", isDefault: true),
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "DOVIWithHDR10",
            dvProfile: 8,
            dvLevel: 6,
            dvBlSignalCompatibilityId: 1,
            whyChosen: "live-player-smoke"
        )

        let reader = HTTPRangeReader(
            url: sourceURL,
            headers: headers,
            config: .init(
                chunkSize: 64 * 1024,
                maxCacheSize: 24 * 1024 * 1024,
                maxRetries: 4,
                baseRetryDelayMs: 150,
                timeoutInterval: 20,
                maxConcurrentRequests: 2,
                readAheadChunks: 0
            )
        )
        let demuxer = MatroskaDemuxer(reader: reader, plan: plan)
        let repackager = FMP4Repackager(plan: plan)
        let session = SyntheticHLSSession(plan: plan, demuxer: demuxer, repackager: repackager)
        try await session.prepare()

        let server = LocalHLSServer(session: session)
        defer {
            server.stop(reason: "test_teardown")
        }
        let baseURL = try server.start()
        let masterURL = baseURL.appendingPathComponent("master.m3u8")

        XCTAssertNotEqual(masterURL.port ?? 0, 0, "Local HLS URL must use non-zero port.")
        XCTAssertFalse(masterURL.absoluteString.contains(":0/"), "Local HLS URL must never contain :0.")

        let master = try await fetchString(from: masterURL)
        XCTAssertTrue(master.contains("#EXTM3U"))

        guard let mediaLine = firstMediaLine(in: master),
              let mediaURL = URL(string: mediaLine, relativeTo: masterURL)?.absoluteURL else {
            XCTFail("Master playlist did not contain child media playlist URI.")
            return
        }

        let media = try await fetchString(from: mediaURL)
        XCTAssertTrue(media.contains("#EXT-X-MAP"))
        XCTAssertTrue(media.contains("#EXTINF"))

        guard let initLine = media.split(whereSeparator: \.isNewline).map(String.init).first(where: { $0.hasPrefix("#EXT-X-MAP:") }),
              let initURI = quotedAttribute("URI", in: initLine),
              let initURL = URL(string: initURI, relativeTo: mediaURL)?.absoluteURL else {
            XCTFail("Media playlist missing init segment map URI.")
            return
        }
        let initData = try await fetchData(from: initURL)
        XCTAssertFalse(initData.isEmpty)
        let initBoxes = try BMFFSanityParser.parseTopLevel(initData)
        XCTAssertTrue(BMFFSanityParser.containsPath(["ftyp"], in: initBoxes))
        XCTAssertTrue(BMFFSanityParser.containsPath(["moov"], in: initBoxes))

        guard let segmentLine = firstMediaLine(in: media),
              let segmentURL = URL(string: segmentLine, relativeTo: mediaURL)?.absoluteURL else {
            XCTFail("Media playlist missing first segment URI.")
            return
        }
        let segmentData = try await fetchData(from: segmentURL)
        XCTAssertFalse(segmentData.isEmpty)
        let segmentBoxes = try BMFFSanityParser.parseTopLevel(segmentData)
        XCTAssertTrue(BMFFSanityParser.containsPath(["moof"], in: segmentBoxes))
        XCTAssertTrue(BMFFSanityParser.containsPath(["mdat"], in: segmentBoxes))
        if let firstTFDT = firstTFDTBaseDecodeTime(in: segmentData) {
            XCTAssertLessThan(
                firstTFDT,
                90000 * 12,
                "First fragment tfdt is unexpectedly large (\(firstTFDT)); timeline should be near start for fast startup."
            )
        }

        let startupResult = try await runAVPlayerStartup(masterURL: masterURL)
        await MainActor.run {
            XCTContext.runActivity(named: "AVPlayer startup snapshot") { activity in
                let snapshot = """
                playable=\(startupResult.playable)
                status=\(startupResult.status.rawValue)
                progressed=\(startupResult.progressed)
                rate=\(startupResult.rate)
                timeControl=\(startupResult.timeControlStatus)
                waitingReason=\(startupResult.waitingReason ?? "none")
                finalTimeSeconds=\(startupResult.finalTimeSeconds)
                """
                activity.add(XCTAttachment(string: snapshot))
            }
        }
        XCTAssertTrue(startupResult.playable, "Synthetic local HLS asset should be playable.")
        if startupResult.status == .failed {
#if targetEnvironment(simulator)
            if startupResult.failureDomain == "CoreMediaErrorDomain" {
                throw XCTSkip(
                    "AVPlayerItem failed on simulator decode stack (\(startupResult.failureDomain ?? "unknown")/\(startupResult.failureCode ?? 0)) after manifest/init/segment fetch succeeded. Validate startup on a physical HDR-capable iPhone/iPad."
                )
            }
#endif
            XCTFail("AVPlayerItem failed with error: \(startupResult.failureMessage ?? "unknown")")
            return
        }
        XCTAssertEqual(startupResult.status, .readyToPlay, "AVPlayerItem should reach readyToPlay for local HLS.")
        if !startupResult.progressed {
#if targetEnvironment(simulator)
            throw XCTSkip(
                "AVPlayerItem reached readyToPlay and segments streamed, but simulator did not advance playback time for this HEVC Main10/E-AC-3 stream. Run this test on an unlocked physical iPhone/iPad to validate decoded-frame startup."
            )
#else
            XCTFail(
                "Playback time should progress after play() for startup proof. status=\(startupResult.status.rawValue) rate=\(startupResult.rate) timeControl=\(startupResult.timeControlStatus) waitingReason=\(startupResult.waitingReason ?? "none") finalTime=\(startupResult.finalTimeSeconds)"
            )
#endif
        }
    }

    private func resolveLiveURL() -> URL? {
        let env = ProcessInfo.processInfo.environment
        if let urlString = env["REELFIN_NATIVEBRIDGE_LIVE_URL"], let url = URL(string: urlString), !urlString.isEmpty {
            return url
        }

        // Fallback for local debugging in CI/simulator where xcodebuild does not propagate env vars.
        let localPath = "/tmp/reelfin_nativebridge_live_url.txt"
        if let raw = try? String(contentsOfFile: localPath, encoding: .utf8) {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: value), !value.isEmpty {
                return url
            }
        }
        return nil
    }

    private func fetchString(from url: URL) async throws -> String {
        let data = try await fetchData(from: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "NativeBridgeLiveURLTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode UTF-8 text from \(url.absoluteString)"])
        }
        return text
    }

    private func fetchData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "NativeBridgeLiveURLTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "HTTP fetch failed for \(url.absoluteString)"])
        }
        return data
    }

    private func firstMediaLine(in playlist: String) -> String? {
        playlist
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { !$0.isEmpty && !$0.hasPrefix("#") })
    }

    private func quotedAttribute(_ name: String, in tagLine: String) -> String? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: name))=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(tagLine.startIndex..<tagLine.endIndex, in: tagLine)
        guard
            let match = regex.firstMatch(in: tagLine, options: [], range: range),
            match.numberOfRanges > 1,
            let valueRange = Range(match.range(at: 1), in: tagLine)
        else {
            return nil
        }
        return String(tagLine[valueRange])
    }

    private func waitForStatus(of playerItem: AVPlayerItem, timeout: TimeInterval) async throws -> AVPlayerItem.Status {
        if playerItem.status != .unknown {
            return playerItem.status
        }

        return try await withCheckedThrowingContinuation { continuation in
            var observation: NSKeyValueObservation?
            var resumed = false

            func finish(_ result: Result<AVPlayerItem.Status, Error>) {
                guard !resumed else { return }
                resumed = true
                observation?.invalidate()
                continuation.resume(with: result)
            }

            observation = playerItem.observe(\.status, options: [.new]) { item, _ in
                if item.status == .readyToPlay || item.status == .failed {
                    finish(.success(item.status))
                }
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                finish(.failure(NSError(domain: "NativeBridgeLiveURLTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for AVPlayerItem status"])))
            }
        }
    }

    private func waitForTimeProgress(player: AVPlayer, minimumSeconds: Double, timeout: TimeInterval) async throws -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            let seconds = player.currentTime().seconds
            if seconds.isFinite, seconds >= minimumSeconds {
                return true
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }

    private func firstTFDTBaseDecodeTime(in fragment: Data) -> UInt64? {
        var offset = 0
        while offset + 8 <= fragment.count {
            let size = Int(fragment[offset]) << 24
                | Int(fragment[offset + 1]) << 16
                | Int(fragment[offset + 2]) << 8
                | Int(fragment[offset + 3])
            guard size >= 8, offset + size <= fragment.count else {
                return nil
            }
            let type = String(data: fragment[(offset + 4)..<(offset + 8)], encoding: .ascii) ?? ""
            if type == "tfdt" {
                let boxPayloadOffset = offset + 8
                guard boxPayloadOffset + 4 <= offset + size else { return nil }
                let version = fragment[boxPayloadOffset]
                let valueOffset = boxPayloadOffset + 4
                if version == 1 {
                    guard valueOffset + 8 <= offset + size else { return nil }
                    return readUInt64BE(fragment, at: valueOffset)
                } else {
                    guard valueOffset + 4 <= offset + size else { return nil }
                    return UInt64(readUInt32BE(fragment, at: valueOffset))
                }
            }
            offset += size
        }
        return nil
    }

    private func readUInt32BE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24
            | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
    }

    private func readUInt64BE(_ data: Data, at offset: Int) -> UInt64 {
        UInt64(readUInt32BE(data, at: offset)) << 32
            | UInt64(readUInt32BE(data, at: offset + 4))
    }

    private struct AVPlayerStartupResult {
        let playable: Bool
        let status: AVPlayerItem.Status
        let progressed: Bool
        let failureMessage: String?
        let failureDomain: String?
        let failureCode: Int?
        let rate: Float
        let timeControlStatus: String
        let waitingReason: String?
        let finalTimeSeconds: Double
    }

    @MainActor
    private func runAVPlayerStartup(masterURL: URL) async throws -> AVPlayerStartupResult {
        let asset = AVURLAsset(url: masterURL)
        let playable = try await asset.load(.isPlayable)

        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer()
        player.replaceCurrentItem(with: playerItem)
        player.automaticallyWaitsToMinimizeStalling = false
        player.play()
        defer {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }

        let status = try await waitForStatus(of: playerItem, timeout: 40)
        let progressed = try await waitForTimeProgress(player: player, minimumSeconds: 0.15, timeout: 20)
        let timeControlStatus: String
        switch player.timeControlStatus {
        case .paused:
            timeControlStatus = "paused"
        case .waitingToPlayAtSpecifiedRate:
            timeControlStatus = "waiting"
        case .playing:
            timeControlStatus = "playing"
        @unknown default:
            timeControlStatus = "unknown"
        }
        return AVPlayerStartupResult(
            playable: playable,
            status: status,
            progressed: progressed,
            failureMessage: playerItem.error?.localizedDescription,
            failureDomain: (playerItem.error as NSError?)?.domain,
            failureCode: (playerItem.error as NSError?)?.code,
            rate: player.rate,
            timeControlStatus: timeControlStatus,
            waitingReason: player.reasonForWaitingToPlay?.rawValue,
            finalTimeSeconds: player.currentTime().seconds
        )
    }
}
