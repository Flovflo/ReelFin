@testable import PlaybackEngine
import AVFoundation
import CoreMedia
import Foundation
import NativeMediaCore
import Network
import QuartzCore
import VideoToolbox
import XCTest

private let validLocalHLSTestHVCC = Data([
    0x01, 0x22, 0x20, 0x00, 0x00, 0x00,
    0x90, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x99, 0xF0, 0x00, 0xFC, 0xFD, 0xFA,
    0xFA, 0x00, 0x00, 0x0F, 0x03,
    0xA0, 0x00, 0x01, 0x00, 0x02, 0x40, 0x01,
    0xA1, 0x00, 0x01, 0x00, 0x02, 0x42, 0x01,
    0xA2, 0x00, 0x01, 0x00, 0x02, 0x44, 0x01
])

final class LocalHLSServerTests: XCTestCase {
    func testIdleReceiveDoesNotRetainServerWhenLastOwnerReleasesIt() async throws {
        let gate = LocalPlaybackConnectionGate(capacity: 1)
        var ownedServer: LocalHLSServer?
        let baseURL: URL
        do {
            let bundle = try await makePreparedServerBundle(
                connectionCapacity: 1,
                connectionGate: gate
            )
            ownedServer = bundle.server
            baseURL = bundle.baseURL
        }
        let serverProbe = HLSWeakServerProbe(server: try XCTUnwrap(ownedServer))
        let client = try makeClient(for: baseURL)
        defer { client.cancel() }
        let peerClosure = HLSPeerClosureProbe()

        client.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, isComplete, error in
            peerClosure.record(isComplete: isComplete, error: error)
        }
        client.start(queue: .global())
        let receiveSuspended = await waitUntil {
            gate.snapshot.active == 1 && serverProbe.receiveStartCount == 1
        }
        XCTAssertTrue(receiveSuspended, "The test must abandon the server while an idle receive is suspended.")

        ownedServer = nil

        let releasedWithoutStop = await waitUntil(timeout: 1) { serverProbe.isReleased }
        XCTAssertTrue(releasedWithoutStop, "An idle receive must not retain LocalHLSServer after its last owner releases it.")
        let peerWasClosed = await waitUntil(timeout: 1) { peerClosure.wasClosed }
        XCTAssertTrue(peerWasClosed, "Deinitialization must close the idle HLS peer without an explicit stop.")
        XCTAssertEqual(gate.snapshot, .init(active: 0, peak: 1, rejected: 0))
    }

    func testLateConnectionCallbackAfterStopIsCancelledBeforeAdmissionOrReceive() async throws {
        let barrier = HLSConnectionCallbackBarrier()
        let serverBundle = try await makePreparedServerBundle(
            connectionCapacity: 1,
            connectionCallbackHook: { barrier.blockFirstCallback() }
        )
        let server = serverBundle.server
        let client = try makeClient(for: serverBundle.baseURL)
        defer { client.cancel() }
        let peerClosure = HLSPeerClosureProbe()

        client.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, isComplete, error in
            peerClosure.record(isComplete: isComplete, error: error)
        }
        client.start(queue: .global())
        let callbackEntered = await waitUntil { barrier.didEnter }
        XCTAssertTrue(callbackEntered)
        server.stop(reason: "test_late_callback_after_stop")
        barrier.release()

        let callbackReturned = await waitUntil { barrier.didReturn }
        XCTAssertTrue(callbackReturned)
        let connectionsDrained = await waitUntil { server.debugActiveConnectionCount == 0 }
        XCTAssertTrue(connectionsDrained)
        let peerWasClosed = await waitUntil { peerClosure.wasClosed }
        XCTAssertTrue(peerWasClosed, "The late accepted socket must be cancelled after stop.")
        XCTAssertEqual(server.debugConnectionSnapshot, .init(active: 0, peak: 0, rejected: 0))
        XCTAssertEqual(server.debugConnectionTaskCount, 0)
        XCTAssertEqual(server.debugReceiveStartCount, 0)
    }

    func testStaleConnectionCallbackAfterRestartCannotEnterNewGeneration() async throws {
        let barrier = HLSConnectionCallbackBarrier()
        let serverBundle = try await makePreparedServerBundle(
            connectionCapacity: 1,
            connectionCallbackHook: { barrier.blockFirstCallback() }
        )
        let server = serverBundle.server
        let staleClient = try makeClient(for: serverBundle.baseURL)
        defer { staleClient.cancel() }
        let peerClosure = HLSPeerClosureProbe()

        staleClient.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, isComplete, error in
            peerClosure.record(isComplete: isComplete, error: error)
        }
        staleClient.start(queue: .global())
        let callbackEntered = await waitUntil { barrier.didEnter }
        XCTAssertTrue(callbackEntered)
        server.stop(reason: "test_stale_callback_restart")
        _ = try server.start()
        defer { server.stop(reason: "test_stale_callback_teardown") }
        barrier.release()

        let callbackReturned = await waitUntil { barrier.didReturn }
        XCTAssertTrue(callbackReturned)
        let peerWasClosed = await waitUntil { peerClosure.wasClosed }
        XCTAssertTrue(peerWasClosed, "A stale-generation socket must be cancelled after restart.")
        XCTAssertEqual(server.debugConnectionSnapshot, .init(active: 0, peak: 0, rejected: 0))
        XCTAssertEqual(server.debugConnectionTaskCount, 0)
        XCTAssertEqual(server.debugReceiveStartCount, 0)
    }

    @MainActor
    func testAVPlayerSyntheticHLSConnectionPeakMeasurement() async throws {
        let serverBundle = try await makeAVPlayerReadableServerBundle(connectionCapacity: nil)
        let server = serverBundle.server
        defer {
            server.stop(reason: "test_teardown_hls_peak")
            XCTAssertNoThrow(try FileManager.default.removeItem(at: serverBundle.fixtureURL))
        }
        let masterURL = serverBundle.baseURL.appendingPathComponent("master.m3u8")

        let asset = AVURLAsset(url: masterURL)
        async let playable = asset.load(.isPlayable)
        async let duration = asset.load(.duration)
        let (isPlayable, loadedDuration) = try await (playable, duration)
        XCTAssertTrue(isPlayable, "The measured HLS fixture must be AVPlayer-readable.")
        XCTAssertTrue(loadedDuration.isValid, "The measured HLS fixture must expose valid duration metadata.")
        XCTAssertTrue(
            loadedDuration.isIndefinite || (loadedDuration.seconds.isFinite && loadedDuration.seconds > 0),
            "The measured HLS EVENT fixture must expose either indefinite live duration or finite positive duration."
        )

        let firstItem = AVPlayerItem(asset: asset)
        let firstVideoOutput = makeVideoOutput()
        firstItem.add(firstVideoOutput)
        let firstPlayer = AVPlayer(playerItem: firstItem)
        firstPlayer.automaticallyWaitsToMinimizeStalling = false
        firstPlayer.play()
        try await requireReady(firstItem, timeout: 10, scenario: "startup")
        firstPlayer.playImmediately(atRate: 1)
        do {
            try await require(
                timeout: 10,
                message: "AVPlayer time did not progress after HLS startup."
            ) { firstPlayer.currentTime().seconds > 0.25 }
        } catch {
            let loadedRanges = firstItem.loadedTimeRanges.map(\.timeRangeValue).map {
                "\($0.start.seconds)...\(CMTimeRangeGetEnd($0).seconds)"
            }
            print(
                "hls.avplayer.progress-diagnostic — rate=\(firstPlayer.rate) "
                    + "timeControlStatus=\(firstPlayer.timeControlStatus.rawValue) "
                    + "reason=\(firstPlayer.reasonForWaitingToPlay?.rawValue ?? "none") "
                    + "bufferEmpty=\(firstItem.isPlaybackBufferEmpty) "
                    + "bufferFull=\(firstItem.isPlaybackBufferFull) "
                    + "likelyToKeepUp=\(firstItem.isPlaybackLikelyToKeepUp) "
                    + "loadedRanges=\(loadedRanges) itemError=\(String(describing: firstItem.error))"
            )
            throw error
        }

        let seekTarget = CMTime(seconds: 2, preferredTimescale: 600)
        let seekCompleted = await withCheckedContinuation { continuation in
            firstPlayer.seek(
                to: seekTarget,
                toleranceBefore: .zero,
                toleranceAfter: .zero,
                completionHandler: { continuation.resume(returning: $0) }
            )
        }
        XCTAssertTrue(seekCompleted, "AVPlayer must complete the measured HLS seek.")
        XCTAssertEqual(firstPlayer.currentTime().seconds, seekTarget.seconds, accuracy: 0.25)
        firstPlayer.play()
        try await require(
            timeout: 5,
            message: "AVPlayer time did not progress after the measured HLS seek."
        ) { firstPlayer.currentTime().seconds > seekTarget.seconds + 0.2 }

        firstPlayer.pause()
        firstPlayer.replaceCurrentItem(with: nil)
        XCTAssertNil(firstPlayer.currentItem, "Stop must detach the first AVPlayer item before replay.")

        let replayItem = AVPlayerItem(url: masterURL)
        let replayVideoOutput = makeVideoOutput()
        replayItem.add(replayVideoOutput)
        let replayPlayer = AVPlayer(playerItem: replayItem)
        replayPlayer.automaticallyWaitsToMinimizeStalling = false
        replayPlayer.play()
        try await requireReady(replayItem, timeout: 10, scenario: "replay")
        replayPlayer.playImmediately(atRate: 1)
        try await require(
            timeout: 10,
            message: "AVPlayer time did not progress during HLS replay."
        ) { replayPlayer.currentTime().seconds > 0.25 }
        replayPlayer.pause()
        let avPlayerPeak = server.debugConnectionSnapshot.peak
        XCTAssertGreaterThan(avPlayerPeak, 0, "AVPlayer itself must contribute measured HLS connections.")

        // Supplemental manifest fan-out remains a distinct scenario; it must not be presented as
        // AVPlayer's socket peak.
        let mediaURL = serverBundle.baseURL.appendingPathComponent("video.m3u8")
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    var request = URLRequest(url: mediaURL)
                    request.cachePolicy = .reloadIgnoringLocalCacheData
                    let (_, response) = try await URLSession.shared.data(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        throw HLSMeasurementError.nonSuccessPlaylistRefresh
                    }
                }
            }
            try await group.waitForAll()
        }

        let measured = server.debugConnectionSnapshot
        print("localplayback.capacity.measurement — lane=hls avplayer_peak=\(avPlayerPeak) supplemental_refresh_peak=\(measured.peak) scenarios=avplayer_startup,metadata,seek,stop_replay+urlsession_playlist_refresh runtime=iOS26.5 admission=disabled")
        XCTAssertGreaterThanOrEqual(measured.peak, avPlayerPeak)
        XCTAssertLessThan(measured.peak, LocalPlaybackServerSecurity.defaultConnectionCapacity)
    }

    @MainActor
    func testAVPlayerSyntheticHEVCMain10SDRCompatibility() async throws {
        let serverBundle = try await makeHEVCMain10SDRServerBundle()
        let server = serverBundle.server
        defer {
            server.stop(reason: "test_teardown_hevc_main10_sdr")
            XCTAssertNoThrow(try FileManager.default.removeItem(at: serverBundle.fixtureURL))
        }
        let directAsset = AVURLAsset(url: serverBundle.fixtureURL)
        let directPlayable = try await directAsset.load(.isPlayable)
        XCTAssertTrue(directPlayable, "Generated HEVC Main10 SDR source fixture must be directly playable.")
        let directItem = AVPlayerItem(asset: directAsset)
        let directOutput = makeVideoOutput(pixelFormat: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
        directItem.add(directOutput)
        let directPlayer = AVPlayer(playerItem: directItem)
        directPlayer.automaticallyWaitsToMinimizeStalling = false
        directPlayer.playImmediately(atRate: 1)
        try await requireReady(directItem, timeout: 15, scenario: "direct HEVC Main10 SDR fixture")
        try await require(timeout: 15, message: "Direct HEVC Main10 SDR fixture did not progress.") {
            directPlayer.currentTime().seconds > 0.25
        }
        directPlayer.pause()
        directPlayer.replaceCurrentItem(with: nil)

        let masterURL = serverBundle.baseURL.appendingPathComponent("master.m3u8")
        let master = try await fetchString(from: masterURL)
        XCTAssertFalse(master.contains("VIDEO-RANGE"), "Main10 SDR must not be advertised as HDR: \(master)")
        XCTAssertTrue(master.contains("CODECS=\"hvc1."), "HEVC fixture must advertise a qualified hvc1 codec: \(master)")
        XCTAssertFalse(master.contains("hvc1.2.4.L153.B0"), "HEVC fixture must not use the removed hard-coded codec.")

        let mediaURL = try XCTUnwrap(
            firstMediaLine(in: master).flatMap { URL(string: $0, relativeTo: masterURL)?.absoluteURL }
        )
        let media = try await fetchString(from: mediaURL)
        let initLine = try XCTUnwrap(media.split(whereSeparator: \.isNewline).map(String.init).first(where: { $0.hasPrefix("#EXT-X-MAP:") }))
        let initURI = try XCTUnwrap(quotedAttribute("URI", in: initLine))
        let initURL = try XCTUnwrap(URL(string: initURI, relativeTo: mediaURL)?.absoluteURL)
        let initData = try await fetchData(from: initURL)
        XCTAssertFalse(initData.isEmpty)
        let segmentURL = try XCTUnwrap(
            firstMediaLine(in: media).flatMap { URL(string: $0, relativeTo: mediaURL)?.absoluteURL }
        )
        let segmentData = try await fetchData(from: segmentURL)
        XCTAssertFalse(segmentData.isEmpty)

        let asset = AVURLAsset(url: masterURL)
        let isPlayable = try await asset.load(.isPlayable)
        XCTAssertTrue(isPlayable, "HEVC Main10 SDR synthetic HLS must be AVPlayer-playable.")
        let firstItem = AVPlayerItem(asset: asset)
        let firstVideoOutput = makeVideoOutput(pixelFormat: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
        firstItem.add(firstVideoOutput)
        let firstPlayer = AVPlayer(playerItem: firstItem)
        firstPlayer.automaticallyWaitsToMinimizeStalling = false
        firstPlayer.playImmediately(atRate: 1)
        try await requireReady(firstItem, timeout: 15, scenario: "HEVC Main10 SDR startup")
        firstPlayer.playImmediately(atRate: 1)
        do {
            try await require(timeout: 15, message: "HEVC Main10 SDR time did not progress.") {
                firstPlayer.currentTime().seconds > 0.25
            }
        } catch {
            let ranges = firstItem.loadedTimeRanges.map(\.timeRangeValue).map {
                "\($0.start.seconds)...\(CMTimeRangeGetEnd($0).seconds)"
            }
            print(
                "hevc.hls.progress-diagnostic — status=\(firstItem.status.rawValue) "
                    + "rate=\(firstPlayer.rate) timeControl=\(firstPlayer.timeControlStatus.rawValue) "
                    + "waiting=\(firstPlayer.reasonForWaitingToPlay?.rawValue ?? "none") "
                    + "bufferEmpty=\(firstItem.isPlaybackBufferEmpty) likelyToKeepUp=\(firstItem.isPlaybackLikelyToKeepUp) "
                    + "ranges=\(ranges) error=\(String(describing: firstItem.error))"
            )
            throw error
        }
        try await require(timeout: 10, message: "HEVC Main10 SDR produced no decoded video frame.") {
            let itemTime = firstVideoOutput.itemTime(forHostTime: CACurrentMediaTime())
            return firstVideoOutput.hasNewPixelBuffer(forItemTime: itemTime)
                && firstVideoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) != nil
        }

        let seekTarget = CMTime(seconds: 2, preferredTimescale: 600)
        let seekCompleted = await withCheckedContinuation { continuation in
            firstPlayer.seek(to: seekTarget, toleranceBefore: .zero, toleranceAfter: .zero) {
                continuation.resume(returning: $0)
            }
        }
        XCTAssertTrue(seekCompleted, "HEVC Main10 SDR seek must complete.")
        XCTAssertEqual(firstPlayer.currentTime().seconds, seekTarget.seconds, accuracy: 0.25)
        firstPlayer.playImmediately(atRate: 1)
        try await require(timeout: 8, message: "HEVC Main10 SDR did not progress after seek.") {
            firstPlayer.currentTime().seconds > seekTarget.seconds + 0.2
        }
        try await require(timeout: 10, message: "HEVC Main10 SDR produced no decoded frame after seek.") {
            let itemTime = firstVideoOutput.itemTime(forHostTime: CACurrentMediaTime())
            return firstVideoOutput.hasNewPixelBuffer(forItemTime: itemTime)
                && firstVideoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) != nil
        }

        firstPlayer.pause()
        firstPlayer.replaceCurrentItem(with: nil)
        XCTAssertNil(firstPlayer.currentItem, "HEVC stop must detach the first item before replay.")

        let replayItem = AVPlayerItem(url: masterURL)
        let replayVideoOutput = makeVideoOutput(pixelFormat: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
        replayItem.add(replayVideoOutput)
        let replayPlayer = AVPlayer(playerItem: replayItem)
        replayPlayer.automaticallyWaitsToMinimizeStalling = false
        replayPlayer.playImmediately(atRate: 1)
        try await requireReady(replayItem, timeout: 15, scenario: "HEVC Main10 SDR replay")
        replayPlayer.playImmediately(atRate: 1)
        try await require(timeout: 15, message: "HEVC Main10 SDR replay did not progress.") {
            replayPlayer.currentTime().seconds > 0.25
        }
        try await require(timeout: 10, message: "HEVC Main10 SDR replay produced no decoded frame.") {
            let itemTime = replayVideoOutput.itemTime(forHostTime: CACurrentMediaTime())
            return replayVideoOutput.hasNewPixelBuffer(forItemTime: itemTime)
                && replayVideoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) != nil
        }
        replayPlayer.pause()
        replayPlayer.replaceCurrentItem(with: nil)
    }

    func testServerUsesCapabilityBasePathAndExplicitLoopbackEndpoint() async throws {
        let serverBundle = try await makePreparedServerBundle(connectionCapacity: nil)
        let server = serverBundle.server
        defer { server.stop(reason: "test_teardown_security_endpoint") }

        XCTAssertEqual(server.debugRequiredLocalEndpoint, .hostPort(host: "127.0.0.1", port: .any))
        let pathComponents = serverBundle.baseURL.pathComponents.filter { $0 != "/" }
        XCTAssertEqual(pathComponents.count, 1)
        XCTAssertEqual(pathComponents[0].count, 64, "The base path must contain one 256-bit capability.")
    }

    func testServerRejectsMissingStalePrefixedPercentEncodedAndNonCanonicalRoutesBeforeDemux() async throws {
        let serverBundle = try await makePreparedServerBundle(connectionCapacity: nil)
        let server = serverBundle.server
        defer { server.stop(reason: "test_teardown_security_routes") }
        let validCapability = try XCTUnwrap(serverBundle.baseURL.pathComponents.last(where: { $0 != "/" }))
        let before = await serverBundle.demuxer.readCount
        let origin = try XCTUnwrap(URL(string: "http://127.0.0.1:\(try XCTUnwrap(serverBundle.baseURL.port))"))
        let bypasses = [
            "/master.m3u8",
            "/\(String(repeating: "0", count: 64))/master.m3u8",
            "/\(validCapability)x/master.m3u8",
            "/\(validCapability)%2Fmaster.m3u8",
            "/\(validCapability)/%2e%2e/master.m3u8",
            "/\(validCapability)/segment_not-a-number.m4s",
            "/\(validCapability)/segment_01.m4s"
        ]

        for path in bypasses {
            let response = try await fetchResponseAllowingError(from: origin.appendingPathComponent(path))
            XCTAssertEqual(response.statusCode, 404, "Unauthorized route must be rejected: \(path)")
        }
        let after = await serverBundle.demuxer.readCount
        XCTAssertEqual(after, before, "Unauthorized routes must not reach demux/repackage work.")
    }

    func testCapabilityRotatesAfterStopAndRestart() async throws {
        let serverBundle = try await makePreparedServerBundle(connectionCapacity: nil)
        let server = serverBundle.server
        let firstURL = serverBundle.baseURL
        server.stop(reason: "test_rotate")

        let secondURL = try server.start()
        defer { server.stop(reason: "test_teardown_rotate") }

        XCTAssertNotEqual(firstURL.path, secondURL.path)
        let stale = try await fetchResponseAllowingError(from: secondURL.deletingLastPathComponent().appendingPathComponent(firstURL.path).appendingPathComponent("master.m3u8"))
        XCTAssertEqual(stale.statusCode, 404)
    }

    func testServerAcquiresCapacityBeforeCreatingConnectionTaskAndStopReleasesIt() async throws {
        let serverBundle = try await makePreparedServerBundle(connectionCapacity: 1)
        let server = serverBundle.server
        defer { server.stop(reason: "test_teardown_capacity") }
        let port = NWEndpoint.Port(rawValue: UInt16(try XCTUnwrap(serverBundle.baseURL.port)))!

        let first = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        first.start(queue: .global())
        defer { first.cancel() }
        let firstAdmitted = await waitUntil { server.debugConnectionSnapshot.active == 1 }
        XCTAssertTrue(firstAdmitted)
        XCTAssertEqual(server.debugConnectionTaskCount, 1)

        let second = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        second.start(queue: .global())
        defer { second.cancel() }
        let secondRejected = await waitUntil { server.debugConnectionSnapshot.rejected == 1 }
        XCTAssertTrue(secondRejected)
        XCTAssertEqual(server.debugConnectionSnapshot.peak, 1)
        XCTAssertEqual(server.debugConnectionTaskCount, 1, "Rejected sockets must not allocate a handler Task.")

        server.stop(reason: "capacity_test_stop")
        let allReleased = await waitUntil { server.debugConnectionSnapshot.active == 0 }
        XCTAssertTrue(allReleased)
        XCTAssertEqual(server.debugConnectionTaskCount, 0)
    }

    func testServerBindsToNonZeroPortAndURLNeverContainsZero() async throws {
        let serverBundle = try await makePreparedServerBundle()
        let server = serverBundle.server
        defer { server.stop(reason: "test_teardown_bind") }

        let masterURL = serverBundle.baseURL.appendingPathComponent("master.m3u8")
        XCTAssertEqual(masterURL.host, "127.0.0.1")
        XCTAssertGreaterThan(masterURL.port ?? 0, 0)
        XCTAssertFalse(masterURL.absoluteString.contains(":0/"))
    }

    func testServerServesMasterAndMediaPlaylistsOverHTTP() async throws {
        let serverBundle = try await makePreparedServerBundle()
        let server = serverBundle.server
        defer { server.stop(reason: "test_teardown_manifest") }

        let masterURL = serverBundle.baseURL.appendingPathComponent("master.m3u8")
        let master = try await fetchString(from: masterURL)
        XCTAssertTrue(master.contains("#EXTM3U"))
        XCTAssertTrue(master.contains("#EXT-X-STREAM-INF"))

        guard let mediaLine = firstMediaLine(in: master),
              let mediaURL = URL(string: mediaLine, relativeTo: masterURL)?.absoluteURL else {
            XCTFail("Master playlist did not include media playlist URI.")
            return
        }

        let media = try await fetchString(from: mediaURL)
        XCTAssertTrue(media.contains("#EXT-X-MAP"))
        XCTAssertTrue(media.contains("#EXTINF"))
    }

    func testServerServesInitSegmentWithBMFFBoxes() async throws {
        let serverBundle = try await makePreparedServerBundle()
        let server = serverBundle.server
        defer { server.stop(reason: "test_teardown_init") }

        let masterURL = serverBundle.baseURL.appendingPathComponent("master.m3u8")
        let master = try await fetchString(from: masterURL)
        guard let mediaLine = firstMediaLine(in: master),
              let mediaURL = URL(string: mediaLine, relativeTo: masterURL)?.absoluteURL else {
            XCTFail("Master playlist did not include media playlist URI.")
            return
        }
        let media = try await fetchString(from: mediaURL)
        guard let mapLine = media.split(whereSeparator: \.isNewline).map(String.init).first(where: { $0.hasPrefix("#EXT-X-MAP:") }),
              let initURI = quotedAttribute("URI", in: mapLine),
              let initURL = URL(string: initURI, relativeTo: mediaURL)?.absoluteURL else {
            XCTFail("Media playlist missing init URI.")
            return
        }

        let initData = try await fetchData(from: initURL)
        XCTAssertFalse(initData.isEmpty)
        let boxes = try BMFFSanityParser.parseTopLevel(initData)
        XCTAssertTrue(BMFFSanityParser.containsPath(["ftyp"], in: boxes))
        XCTAssertTrue(BMFFSanityParser.containsPath(["moov"], in: boxes))
    }

    func testServerServesFirstSegmentWithBMFFBoxes() async throws {
        let serverBundle = try await makePreparedServerBundle()
        let server = serverBundle.server
        defer { server.stop(reason: "test_teardown_segment") }

        let masterURL = serverBundle.baseURL.appendingPathComponent("master.m3u8")
        let master = try await fetchString(from: masterURL)
        guard let mediaLine = firstMediaLine(in: master),
              let mediaURL = URL(string: mediaLine, relativeTo: masterURL)?.absoluteURL else {
            XCTFail("Master playlist did not include media playlist URI.")
            return
        }
        let media = try await fetchString(from: mediaURL)
        guard let segmentLine = firstMediaLine(in: media),
              let segmentURL = URL(string: segmentLine, relativeTo: mediaURL)?.absoluteURL else {
            XCTFail("Media playlist missing first segment URI.")
            return
        }

        let segmentData = try await fetchData(from: segmentURL)
        XCTAssertFalse(segmentData.isEmpty)
        let boxes = try BMFFSanityParser.parseTopLevel(segmentData)
        XCTAssertTrue(BMFFSanityParser.containsPath(["moof"], in: boxes))
        XCTAssertTrue(BMFFSanityParser.containsPath(["mdat"], in: boxes))
    }

    func testServerStateTransitionsFromListeningToServing() async throws {
        let serverBundle = try await makePreparedServerBundle()
        let server = serverBundle.server
        defer { server.stop(reason: "test_teardown_state") }

        let initial = server.currentState()
        switch initial {
        case .listening(_, let port):
            XCTAssertGreaterThan(port, 0)
        case .serving(_, let port, _):
            XCTAssertGreaterThan(port, 0)
        default:
            XCTFail("Expected server to be listening or serving after start, got \(initial)")
        }

        _ = try await fetchString(from: serverBundle.baseURL.appendingPathComponent("master.m3u8"))

        let serving = server.currentState()
        switch serving {
        case .serving(_, let port, let requestsServed):
            XCTAssertGreaterThan(port, 0)
            XCTAssertGreaterThanOrEqual(requestsServed, 1)
        default:
            XCTFail("Expected server to be serving after a request, got \(serving)")
        }
    }

    func testStartupSnapshotModeServesVODSingleSegmentWithEndList() async throws {
        let serverBundle = try await makePreparedServerBundle()
        let server = serverBundle.server
        defer { server.stop(reason: "test_teardown_snapshot_mode") }
        server.setStartupPreflightSnapshotMode(true)

        let mediaURL = serverBundle.baseURL.appendingPathComponent("video.m3u8")
        let media = try await fetchString(from: mediaURL)

        XCTAssertTrue(media.contains("#EXT-X-PLAYLIST-TYPE:VOD"))
        XCTAssertTrue(media.contains("#EXT-X-ENDLIST"))
        XCTAssertEqual(
            media.split(whereSeparator: \.isNewline).filter { $0.contains("segment_") }.count,
            1
        )
    }

    func testServerUsesImmutableCacheHeadersForInitAndSegmentsButNotPlaylist() async throws {
        let serverBundle = try await makePreparedServerBundle()
        let server = serverBundle.server
        defer { server.stop(reason: "test_teardown_cache_headers") }

        let playlistResponse = try await fetchResponse(from: serverBundle.baseURL.appendingPathComponent("video.m3u8"))
        XCTAssertEqual(playlistResponse.value(forHTTPHeaderField: "Cache-Control"), "no-cache")

        let initResponse = try await fetchResponse(from: serverBundle.baseURL.appendingPathComponent("init.mp4"))
        XCTAssertEqual(initResponse.value(forHTTPHeaderField: "Cache-Control"), "public, max-age=31536000, immutable")

        let segmentResponse = try await fetchResponse(from: serverBundle.baseURL.appendingPathComponent("segment_0.m4s"))
        XCTAssertEqual(segmentResponse.value(forHTTPHeaderField: "Cache-Control"), "public, max-age=31536000, immutable")
    }

    private func makeAVPlayerReadableServerBundle(
        connectionCapacity: Int?
    ) async throws -> (server: LocalHLSServer, baseURL: URL, fixtureURL: URL) {
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReelFin-HLS-Measurement-\(UUID().uuidString).mp4")
        do {
            try PlaybackDropResilienceTests.generateClip(
                to: fixtureURL,
                seconds: 20,
                fps: 30,
                width: 480,
                height: 270,
                allowFrameReordering: false
            )
            let demuxer = try MP4HLSFixtureDemuxer(url: fixtureURL, width: 480, height: 270)
            let streamInfo = try await demuxer.open()
            let videoTrack = try XCTUnwrap(streamInfo.primaryVideoTrack)
            guard try await demuxer.readSample() != nil else {
                throw HLSMeasurementError.fixtureDemuxProducedNoVideo
            }
            _ = try await demuxer.seek(to: 0)
            let plan = NativeBridgePlan(
                itemID: "local-hls-avplayer-measurement",
                sourceID: "local-hls-avplayer-source",
                sourceURL: fixtureURL,
                videoTrack: videoTrack,
                audioTrack: nil,
                videoAction: .directPassthrough,
                audioAction: .directPassthrough,
                subtitleTracks: [],
                videoRangeType: "SDR",
                whyChosen: "avplayer-readable-hls-measurement"
            )
            let repackager = FMP4Repackager(plan: plan)
            let session = SyntheticHLSSession(plan: plan, demuxer: demuxer, repackager: repackager)
            try await session.prepare()
            let server = LocalHLSServer(session: session, connectionCapacity: connectionCapacity)
            return (server, try server.start(), fixtureURL)
        } catch {
            let fixtureError = error
            XCTAssertNoThrow(try FileManager.default.removeItem(at: fixtureURL))
            throw fixtureError
        }
    }

    private func makeHEVCMain10SDRServerBundle() async throws -> (server: LocalHLSServer, baseURL: URL, fixtureURL: URL) {
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReelFin-HEVC-Main10-SDR-\(UUID().uuidString).mp4")
        do {
            try HEVCMain10SDRFixture.generate(to: fixtureURL, seconds: 8, fps: 30, width: 480, height: 270)
            let demuxer = try MP4HLSFixtureDemuxer(url: fixtureURL, width: 480, height: 270, bitDepth: 10)
            let streamInfo = try await demuxer.open()
            let videoTrack = try XCTUnwrap(streamInfo.primaryVideoTrack)
            XCTAssertTrue(videoTrack.codecName.lowercased().contains("hevc") || videoTrack.codecName.lowercased().contains("hvc1"))
            XCTAssertGreaterThanOrEqual(videoTrack.codecPrivate?.count ?? 0, 13)
            guard try await demuxer.readSample() != nil else {
                throw HLSMeasurementError.fixtureDemuxProducedNoVideo
            }
            _ = try await demuxer.seek(to: 0)
            let plan = NativeBridgePlan(
                itemID: "local-hls-hevc-main10-sdr",
                sourceID: "local-hls-hevc-main10-sdr-source",
                sourceURL: fixtureURL,
                videoTrack: videoTrack,
                audioTrack: nil,
                videoAction: .directPassthrough,
                audioAction: .directPassthrough,
                subtitleTracks: [],
                videoRangeType: "SDR",
                whyChosen: "real-hevc-main10-sdr-avplayer-gate"
            )
            let repackager = FMP4Repackager(plan: plan)
            let session = SyntheticHLSSession(
                plan: plan,
                demuxer: demuxer,
                repackager: repackager,
                packagingMode: .hdr10OnlyFallback
            )
            try await session.prepare()
            let server = LocalHLSServer(session: session)
            return (server, try server.start(), fixtureURL)
        } catch {
            let fixtureError = error
            try? FileManager.default.removeItem(at: fixtureURL)
            throw fixtureError
        }
    }

    private func makePreparedServerBundle(
        connectionCapacity: Int? = LocalPlaybackServerSecurity.defaultConnectionCapacity,
        connectionGate: LocalPlaybackConnectionGate? = nil,
        connectionCallbackHook: (@Sendable () -> Void)? = nil
    ) async throws -> (server: LocalHLSServer, baseURL: URL, demuxer: LocalHLSTestDemuxer) {
        let plan = NativeBridgePlan(
            itemID: "local-hls-test-item",
            sourceID: "local-hls-test-source",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: TrackInfo(
                id: 1,
                trackType: .video,
                codecID: "V_MPEGH/ISO/HEVC",
                codecName: "hevc",
                isDefault: true,
                width: 1920,
                height: 1080,
                bitDepth: 10,
                codecPrivate: validLocalHLSTestHVCC
            ),
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "HDR10",
            whyChosen: "local-hls-tests"
        )

        let demuxer = LocalHLSTestDemuxer(samples: makeSamples(count: 100), track: plan.videoTrack)
        let repackager = FMP4Repackager(plan: plan)
        let session = SyntheticHLSSession(plan: plan, demuxer: demuxer, repackager: repackager)
        try await session.prepare()

        let server = LocalHLSServer(
            session: session,
            connectionCapacity: connectionCapacity,
            connectionGate: connectionGate,
            connectionCallbackHook: connectionCallbackHook
        )
        let baseURL = try server.start()
        return (server, baseURL, demuxer)
    }

    private func makeSamples(count: Int) -> [Sample] {
        let frameNs: Int64 = 41_708_333
        return (0..<count).map { idx in
            let ptsValue = Int64(idx) * frameNs
            return Sample(
                trackID: 1,
                pts: CMTime(value: ptsValue, timescale: 1_000_000_000),
                duration: CMTime(value: frameNs, timescale: 1_000_000_000),
                isKeyframe: idx % 24 == 0,
                data: Data([
                    0x00, 0x00, 0x01, 0x65, 0x88, UInt8(idx % 255),
                    0x00, 0x00, 0x00, 0x01, 0x41, 0x99, 0xAA
                ])
            )
        }
    }

    private func fetchString(from url: URL) async throws -> String {
        let data = try await fetchData(from: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "LocalHLSServerTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode UTF-8 body from \(url.absoluteString)"])
        }
        return text
    }

    private func fetchData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "LocalHLSServerTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "HTTP fetch failed for \(url.absoluteString)"])
        }
        return data
    }

    private func fetchResponse(from url: URL) async throws -> HTTPURLResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "LocalHLSServerTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "HTTP response fetch failed for \(url.absoluteString)"])
        }
        return http
    }

    private func fetchResponseAllowingError(from url: URL) async throws -> HTTPURLResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        let (_, response) = try await URLSession.shared.data(for: request)
        return try XCTUnwrap(response as? HTTPURLResponse)
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: @escaping @Sendable () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    @MainActor
    private func requireReady(
        _ item: AVPlayerItem,
        timeout: TimeInterval,
        scenario: String
    ) async throws {
        try await require(timeout: timeout, message: "AVPlayer item stayed unknown during \(scenario).") {
            item.status != .unknown
        }
        switch item.status {
        case .readyToPlay:
            return
        case .failed:
            throw item.error ?? HLSMeasurementError.playerFailed(scenario)
        case .unknown:
            throw HLSMeasurementError.timedOut(scenario)
        @unknown default:
            throw HLSMeasurementError.playerFailed(scenario)
        }
    }

    @MainActor
    private func require(
        timeout: TimeInterval,
        message: String,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard condition() else {
            XCTFail(message)
            throw HLSMeasurementError.timedOut(message)
        }
    }

    private func makeClient(for baseURL: URL) throws -> NWConnection {
        let rawPort = try XCTUnwrap(baseURL.port)
        let port = try XCTUnwrap(NWEndpoint.Port(rawValue: UInt16(rawPort)))
        return NWConnection(host: "127.0.0.1", port: port, using: .tcp)
    }

    private func makeVideoOutput(
        pixelFormat: OSType = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    ) -> AVPlayerItemVideoOutput {
        AVPlayerItemVideoOutput(
            pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(pixelFormat)
            ]
        )
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
}

private enum HLSMeasurementError: Error {
    case timedOut(String)
    case playerFailed(String)
    case nonSuccessPlaylistRefresh
    case fixtureDemuxProducedNoVideo
}

private final class HLSConnectionCallbackBarrier: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var shouldBlock = true
    private var entered = false
    private var returned = false

    var didEnter: Bool { lock.withLock { entered } }
    var didReturn: Bool { lock.withLock { returned } }

    func blockFirstCallback() {
        let blocks = lock.withLock { () -> Bool in
            guard shouldBlock else { return false }
            shouldBlock = false
            entered = true
            return true
        }
        guard blocks else { return }
        semaphore.wait()
        lock.withLock { returned = true }
    }

    func release() {
        semaphore.signal()
    }
}

private final class HLSPeerClosureProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false

    var wasClosed: Bool { lock.withLock { closed } }

    func record(isComplete: Bool, error: NWError?) {
        lock.withLock { closed = isComplete || error != nil }
    }
}

private final class HLSWeakServerProbe: @unchecked Sendable {
    private weak var server: LocalHLSServer?

    init(server: LocalHLSServer) {
        self.server = server
    }

    var isReleased: Bool { server == nil }
    var receiveStartCount: Int { server?.debugReceiveStartCount ?? 0 }
}

private enum HEVCMain10SDRFixture {
    static func generate(to url: URL, seconds: Int, fps: Int, width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
                ],
                AVVideoCompressionPropertiesKey: [
                    AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel,
                    AVVideoAverageBitRateKey: 2_500_000,
                    AVVideoAllowFrameReorderingKey: false,
                    AVVideoMaxKeyFrameIntervalKey: fps
                ]
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        guard writer.canAdd(input) else {
            throw NSError(domain: "HEVCMain10SDRFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter rejected HEVC Main10 input."])
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "HEVCMain10SDRFixture", code: 2)
        }
        writer.startSession(atSourceTime: .zero)

        let totalFrames = seconds * fps
        var frameIndex = 0
        let completion = DispatchSemaphore(value: 0)
        input.requestMediaDataWhenReady(on: DispatchQueue(label: "reelfin.fixture.hevc-main10")) {
            while input.isReadyForMoreMediaData {
                guard frameIndex < totalFrames else {
                    input.markAsFinished()
                    completion.signal()
                    return
                }
                guard let pool = adaptor.pixelBufferPool else {
                    writer.cancelWriting()
                    completion.signal()
                    return
                }
                var pixelBuffer: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
                      let pixelBuffer else {
                    writer.cancelWriting()
                    completion.signal()
                    return
                }
                fill(pixelBuffer, frameIndex: frameIndex)
                let time = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(fps))
                guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
                    writer.cancelWriting()
                    completion.signal()
                    return
                }
                frameIndex += 1
            }
        }
        completion.wait()
        guard writer.status != .cancelled else {
            throw writer.error ?? NSError(domain: "HEVCMain10SDRFixture", code: 3)
        }
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        guard writer.status == .completed else {
            throw writer.error ?? NSError(domain: "HEVCMain10SDRFixture", code: 4, userInfo: [NSLocalizedDescriptionKey: "HEVC Main10 fixture write failed."])
        }
    }

    private static func fill(_ pixelBuffer: CVPixelBuffer, frameIndex: Int) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard CVPixelBufferGetPlaneCount(pixelBuffer) == 2 else { return }

        let lumaBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)!.assumingMemoryBound(to: UInt16.self)
        let lumaWordsPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0) / MemoryLayout<UInt16>.size
        let lumaWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let lumaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        for y in 0..<lumaHeight {
            for x in 0..<lumaWidth {
                let value = UInt16(64 + ((x + y + frameIndex * 3) % 876))
                lumaBase[y * lumaWordsPerRow + x] = value << 6
            }
        }

        let chromaBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)!.assumingMemoryBound(to: UInt16.self)
        let chromaWordsPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1) / MemoryLayout<UInt16>.size
        let chromaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        let neutral = UInt16(512 << 6)
        for y in 0..<chromaHeight {
            for x in 0..<chromaWordsPerRow {
                chromaBase[y * chromaWordsPerRow + x] = neutral
            }
        }
    }
}

private actor MP4HLSFixtureDemuxer: Demuxer {
    private let demuxer: NativeMediaCore.MP4Demuxer
    private let width: Int
    private let height: Int
    private let bitDepth: Int
    private var cachedInfo: StreamInfo?

    init(url: URL, width: Int, height: Int, bitDepth: Int = 8) throws {
        self.demuxer = try NativeMediaCore.MP4Demuxer(url: url, format: .mp4)
        self.width = width
        self.height = height
        self.bitDepth = bitDepth
    }

    func open() async throws -> StreamInfo {
        if let cachedInfo { return cachedInfo }
        let source = try await demuxer.open()
        let tracks = source.tracks.compactMap { track -> TrackInfo? in
            guard track.kind == .video else { return nil }
            return TrackInfo(
                id: track.trackId,
                trackType: .video,
                codecID: track.codecID ?? "avc1",
                codecName: track.codec,
                language: track.language,
                isDefault: track.isDefault,
                width: width,
                height: height,
                bitDepth: bitDepth,
                codecPrivate: track.codecPrivateData
            )
        }
        let info = StreamInfo(
            durationNanoseconds: Self.nanoseconds(source.duration ?? .zero),
            tracks: tracks,
            hasChapters: false,
            seekable: source.seekMap.isSeekable
        )
        cachedInfo = info
        return info
    }

    func readPacket() async throws -> DemuxedPacket? {
        guard let packet = try await nextVideoPacket() else { return nil }
        return DemuxedPacket(
            trackID: packet.trackID,
            timestamp: Self.nanoseconds(packet.timestamp.pts),
            duration: Self.nanoseconds(packet.timestamp.duration ?? .zero),
            isKeyframe: packet.isKeyframe,
            data: packet.data
        )
    }

    func readSample() async throws -> Sample? {
        guard let packet = try await nextVideoPacket() else { return nil }
        return Sample(
            trackID: packet.trackID,
            pts: packet.timestamp.pts,
            dts: packet.timestamp.dts,
            duration: packet.timestamp.duration ?? .zero,
            isKeyframe: packet.isKeyframe,
            data: packet.data
        )
    }

    func seek(to timeNanoseconds: Int64) async throws -> Int64 {
        let target = CMTime(value: timeNanoseconds, timescale: 1_000_000_000)
        try await demuxer.seek(to: target)
        return timeNanoseconds
    }

    private func nextVideoPacket() async throws -> NativeMediaCore.MediaPacket? {
        let videoTrackIDs = Set((try await open()).videoTracks.map(\.id))
        for _ in 0..<100 {
            if let packet = try await demuxer.readNextPacket() {
                if videoTrackIDs.contains(packet.trackID) { return packet }
            } else {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        return nil
    }

    private static func nanoseconds(_ time: CMTime) -> Int64 {
        guard time.isValid, !time.isIndefinite else { return 0 }
        return CMTimeConvertScale(time, timescale: 1_000_000_000, method: .default).value
    }
}

private actor LocalHLSTestDemuxer: Demuxer {
    private let samples: [Sample]
    private let track: TrackInfo
    private var index: Int = 0

    var readCount: Int { index }

    init(samples: [Sample], track: TrackInfo) {
        self.samples = samples
        self.track = track
    }

    func open() async throws -> StreamInfo {
        StreamInfo(
            durationNanoseconds: Int64(samples.count) * 41_708_333,
            tracks: [track],
            hasChapters: false,
            seekable: true
        )
    }

    func readPacket() async throws -> DemuxedPacket? {
        guard index < samples.count else { return nil }
        defer { index += 1 }
        return DemuxedPacket(sample: samples[index])
    }

    func readSample() async throws -> Sample? {
        guard index < samples.count else { return nil }
        defer { index += 1 }
        return samples[index]
    }

    func seek(to timeNanoseconds: Int64) async throws -> Int64 {
        if let idx = samples.firstIndex(where: { $0.ptsNanoseconds >= timeNanoseconds }) {
            index = idx
            return samples[idx].ptsNanoseconds
        }
        index = samples.count
        return timeNanoseconds
    }
}
