import Foundation
@testable import PlaybackEngine
import Shared
import XCTest

final class PlaybackStartupPreheaterTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PlaybackStartupFixtureURLProtocol.reset(storage: Data())
    }

    func testPreheatSkipsLocalAssetsWithoutNetworkRequest() async {
        let selection = makeDirectPlaySelection(
            assetURL: URL(string: "https://localhost/video.mp4")!,
            sourceFileSize: 10 * 1_048_576,
            sourceBitrate: 12_000_000
        )

        let result = await PlaybackStartupPreheater.preheat(
            selection: selection,
            resumeSeconds: 2,
            runtimeSeconds: 100,
            isTVOS: false
        )

        XCTAssertNil(result)
        XCTAssertEqual(PlaybackStartupFixtureURLProtocol.requestCount, 0)
    }

    func testPreheatSkipsWhenReadinessPolicyReturnsNil() async {
        let selection = makeDirectPlaySelection(
            sourceBitrate: 8_000_000
        )

        let result = await PlaybackStartupPreheater.preheat(
            selection: selection,
            resumeSeconds: 0,
            runtimeSeconds: nil,
            isTVOS: false
        )

        XCTAssertNil(result)
        XCTAssertEqual(PlaybackStartupFixtureURLProtocol.requestCount, 0)
    }

    func testPreheatSkipsLowBitrateIPhoneProgressiveDirectPlayEvenWhenResuming() async {
        let selection = makeDirectPlaySelection(
            sourceBitrate: 1_000_000
        )

        let result = await PlaybackStartupPreheater.preheat(
            selection: selection,
            resumeSeconds: 1_000,
            runtimeSeconds: 7_200,
            isTVOS: false
        )

        XCTAssertNil(result)
        XCTAssertEqual(PlaybackStartupFixtureURLProtocol.requestCount, 0)
    }

    func testPreheatUsesIPhoneProgressiveDirectPlayRangeProbe() async throws {
        let selection = makeDirectPlaySelection(
            sourceFileSize: 100 * 1_048_576,
            sourceBitrate: 22_000_000,
            headers: ["X-Auth-Token": "token-123"]
        )
        PlaybackStartupFixtureURLProtocol.reset(storage: Data(repeating: 0xAB, count: 24 * 1_048_576))

        let result = await PlaybackStartupPreheater.preheat(
            selection: selection,
            resumeSeconds: 20,
            runtimeSeconds: 100,
            isTVOS: false,
            urlProtocolClasses: [PlaybackStartupFixtureURLProtocol.self]
        )

        XCTAssertEqual(result?.byteCount, 12 * 1_048_576)
        XCTAssertEqual(result?.rangeStart, 12 * 1_048_576)
        XCTAssertEqual(result?.reason, "directplay_range_deep")
        XCTAssertEqual(PlaybackStartupFixtureURLProtocol.requestCount, 1)

        let request = try XCTUnwrap(PlaybackStartupFixtureURLProtocol.capturedRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=12582912-25165823")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Auth-Token"), "token-123")
    }

    func testPreheatUsesTvOSProgressiveDirectPlayRangeProbe() async throws {
        let selection = makeDirectPlaySelection(
            sourceFileSize: 10 * 1_048_576,
            sourceBitrate: 12_000_000,
            headers: ["X-Auth-Token": "token-123"]
        )
        PlaybackStartupFixtureURLProtocol.reset(storage: Data(repeating: 0xAB, count: 4 * 1_048_576))

        let result = await PlaybackStartupPreheater.preheat(
            selection: selection,
            resumeSeconds: 20,
            runtimeSeconds: 100,
            isTVOS: true,
            urlProtocolClasses: [PlaybackStartupFixtureURLProtocol.self]
        )

        XCTAssertEqual(result?.byteCount, 4 * 1_048_576)
        XCTAssertEqual(result?.rangeStart, 0)
        XCTAssertEqual(result?.reason, "directplay_range")
        XCTAssertEqual(PlaybackStartupFixtureURLProtocol.requestCount, 1)

        let request = try XCTUnwrap(PlaybackStartupFixtureURLProtocol.capturedRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=0-4194303")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Auth-Token"), "token-123")
    }

    func testPreheatCapsDeepIPhoneDirectPlayRangeAtKnownFileEnd() async throws {
        let selection = makeDirectPlaySelection(
            sourceFileSize: 14 * 1_048_576,
            sourceBitrate: 22_000_000
        )
        PlaybackStartupFixtureURLProtocol.reset(storage: Data(repeating: 0xAB, count: 14 * 1_048_576))

        let result = await PlaybackStartupPreheater.preheat(
            selection: selection,
            resumeSeconds: 95,
            runtimeSeconds: 100,
            isTVOS: false,
            urlProtocolClasses: [PlaybackStartupFixtureURLProtocol.self]
        )

        XCTAssertEqual(result?.byteCount, 2 * 1_048_576)
        XCTAssertEqual(result?.rangeStart, 12 * 1_048_576)
        XCTAssertEqual(result?.reason, "directplay_range_deep")

        let request = try XCTUnwrap(PlaybackStartupFixtureURLProtocol.capturedRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=12582912-14680063")
    }

    func testPreheatSkipsIPhoneHLSPlaylistProbe() async {
        let selection = makeDirectPlaySelection(
            assetURL: URL(string: "https://fixture.local/master.m3u8")!,
            sourceFileSize: 10 * 1_048_576,
            sourceBitrate: 12_000_000
        )
        PlaybackStartupFixtureURLProtocol.reset(storage: Data(repeating: 0xEE, count: 600 * 1024))

        let result = await PlaybackStartupPreheater.preheat(
            selection: selection,
            resumeSeconds: 20,
            runtimeSeconds: 100,
            isTVOS: false,
            urlProtocolClasses: [PlaybackStartupFixtureURLProtocol.self]
        )

        XCTAssertNil(result)
        XCTAssertEqual(PlaybackStartupFixtureURLProtocol.requestCount, 0)
    }

    func testPreheatKeepsTvOSHLSPlaylistProbeWithoutRangeRequest() async throws {
        let selection = makeDirectPlaySelection(
            assetURL: URL(string: "https://fixture.local/master.m3u8")!,
            sourceFileSize: 10 * 1_048_576,
            sourceBitrate: 12_000_000
        )
        PlaybackStartupFixtureURLProtocol.reset(storage: Data(repeating: 0xEE, count: 600 * 1024))

        let result = await PlaybackStartupPreheater.preheat(
            selection: selection,
            resumeSeconds: 20,
            runtimeSeconds: 100,
            isTVOS: true,
            urlProtocolClasses: [PlaybackStartupFixtureURLProtocol.self]
        )

        XCTAssertEqual(result?.byteCount, 512 * 1024)
        XCTAssertNil(result?.rangeStart)
        XCTAssertEqual(result?.reason, "playlist_probe")

        let request = try XCTUnwrap(PlaybackStartupFixtureURLProtocol.capturedRequest)
        XCTAssertNil(request.value(forHTTPHeaderField: "Range"))
    }

    func testPreheatTruncatesPlaylistProbeResponseAndOmitsRangeHeader() async throws {
        let selection = makeNativeBridgeSelection()
        PlaybackStartupFixtureURLProtocol.reset(storage: Data(repeating: 0xCD, count: 600 * 1024))

        let result = await PlaybackStartupPreheater.preheat(
            selection: selection,
            resumeSeconds: 0,
            runtimeSeconds: nil,
            isTVOS: false,
            urlProtocolClasses: [PlaybackStartupFixtureURLProtocol.self]
        )

        XCTAssertEqual(result?.byteCount, 256 * 1024)
        XCTAssertNil(result?.rangeStart)
        XCTAssertEqual(result?.reason, "playlist_probe")

        let request = try XCTUnwrap(PlaybackStartupFixtureURLProtocol.capturedRequest)
        XCTAssertNil(request.value(forHTTPHeaderField: "Range"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "*/*")
    }

    private func makeDirectPlaySelection(
        assetURL: URL = URL(string: "https://fixture.local/video.mp4")!,
        sourceFileSize: Int64 = 10 * 1_048_576,
        sourceBitrate: Int? = 12_000_000,
        headers: [String: String] = [:]
    ) -> PlaybackAssetSelection {
        PlaybackAssetSelection(
            source: MediaSource(
                id: "item-1",
                itemID: "item-1",
                name: "Test Item",
                fileSize: sourceFileSize,
                bitrate: sourceBitrate,
                supportsDirectPlay: true,
                supportsDirectStream: true,
                directStreamURL: URL(string: "https://fixture.local/master.m3u8"),
                directPlayURL: assetURL,
                transcodeURL: URL(string: "https://fixture.local/transcode.m3u8")
            ),
            decision: PlaybackDecision(
                sourceID: "source-1",
                route: .directPlay(assetURL)
            ),
            assetURL: assetURL,
            headers: headers,
            debugInfo: PlaybackDebugInfo(
                container: "mp4",
                videoCodec: "hevc",
                videoBitDepth: 10,
                hdrMode: .sdr,
                audioMode: "aac",
                bitrate: sourceBitrate,
                playMethod: "DirectPlay"
            )
        )
    }

    private func makeNativeBridgeSelection() -> PlaybackAssetSelection {
        let assetURL = URL(string: "https://fixture.local/master.m3u8")!
        return PlaybackAssetSelection(
            source: MediaSource(
                id: "item-2",
                itemID: "item-2",
                name: "Bridge Item",
                supportsDirectPlay: false,
                supportsDirectStream: true,
                directStreamURL: assetURL,
                transcodeURL: assetURL
            ),
            decision: PlaybackDecision(
                sourceID: "source-2",
                route: .nativeBridge(
                    NativeBridgePlan(
                        itemID: "item-2",
                        sourceID: "source-2",
                        sourceURL: assetURL,
                        videoTrack: TrackInfo(
                            id: 1,
                            trackType: .video,
                            codecID: "V_MPEGH/ISO/HEVC",
                            codecName: "hevc",
                            isDefault: true
                        ),
                        audioTrack: nil,
                        videoAction: .directPassthrough,
                        audioAction: .directPassthrough,
                        subtitleTracks: [],
                        whyChosen: "test"
                    )
                )
            ),
            assetURL: assetURL,
            headers: [:],
            debugInfo: PlaybackDebugInfo(
                container: "mkv",
                videoCodec: "hevc",
                videoBitDepth: 10,
                hdrMode: .sdr,
                audioMode: "aac",
                bitrate: nil,
                playMethod: "NativeBridge"
            )
        )
    }
}

private final class PlaybackStartupFixtureURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var storage = Data()
    private static var _capturedRequest: URLRequest?
    private static var _requestCount = 0

    static var capturedRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return _capturedRequest
    }

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _requestCount
    }

    static func reset(storage: Data) {
        lock.lock()
        defer { lock.unlock() }
        self.storage = storage
        _capturedRequest = nil
        _requestCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "fixture.local" || request.url?.host == "localhost"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.record(request)

        let data = Self.storageSnapshot()
        if let rangeHeader = request.value(forHTTPHeaderField: "Range"),
           let range = parseRange(rangeHeader, upperBound: data.count) {
            let slice = data[range]
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 206,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Range": "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(data.count)",
                    "Content-Length": "\(slice.count)"
                ]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(slice))
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "\(data.count)"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func record(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        _capturedRequest = request
        _requestCount += 1
    }

    private static func storageSnapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    private func parseRange(_ value: String, upperBound: Int) -> Range<Int>? {
        guard value.hasPrefix("bytes=") else { return nil }
        let parts = value.dropFirst("bytes=".count).split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let start = Int(parts[0]),
              let end = Int(parts[1]),
              start >= 0,
              end >= start else { return nil }
        let boundedEnd = min(end, max(0, upperBound - 1))
        return start..<(boundedEnd + 1)
    }
}
