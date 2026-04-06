@testable import PlaybackEngine
import CoreMedia
import Foundation
import XCTest

final class LocalHLSServerTests: XCTestCase {
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

    private func makePreparedServerBundle() async throws -> (server: LocalHLSServer, baseURL: URL) {
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
                codecPrivate: Data([0x01, 0x01, 0x60, 0x00])
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

        let server = LocalHLSServer(session: session)
        let baseURL = try server.start()
        return (server, baseURL)
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

private actor LocalHLSTestDemuxer: Demuxer {
    private let samples: [Sample]
    private let track: TrackInfo
    private var index: Int = 0

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
