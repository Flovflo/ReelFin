@testable import PlaybackEngine
import Foundation
import XCTest

final class NativeBridgeIntegrationTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        URLProtocol.registerClass(FixtureRangeURLProtocol.self)
    }

    override class func tearDown() {
        URLProtocol.unregisterClass(FixtureRangeURLProtocol.self)
        super.tearDown()
    }

    func testDemuxAndRepackageFromFixtureIfProvided() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["REELFIN_NATIVEBRIDGE_DV_FIXTURE_PATH"], !path.isEmpty else {
            throw XCTSkip("Set REELFIN_NATIVEBRIDGE_DV_FIXTURE_PATH for full MKV integration test.")
        }

        let fixtureData = try Data(contentsOf: URL(fileURLWithPath: path))
        FixtureRangeURLProtocol.storage = fixtureData

        let plan = NativeBridgePlan(
            itemID: "fixture-item",
            sourceID: "fixture-source",
            sourceURL: URL(string: "https://fixture.local/video.mkv")!,
            videoTrack: TrackInfo(id: 1, trackType: .video, codecID: "V_MPEGH/ISO/HEVC", codecName: "hevc", isDefault: true),
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "DOVIWithHDR10",
            dvProfile: 8,
            dvLevel: 6,
            dvBlSignalCompatibilityId: 1,
            whyChosen: "fixture"
        )

        let reader = HTTPRangeReader(url: plan.sourceURL, headers: [:], config: .init(chunkSize: 512 * 1024, maxCacheSize: 8 * 1024 * 1024, maxRetries: 2, baseRetryDelayMs: 25, timeoutInterval: 10, maxConcurrentRequests: 2, readAheadChunks: 0))
        let demuxer = MatroskaDemuxer(reader: reader, plan: plan)
        let repackager = FMP4Repackager(plan: plan)

        let streamInfo = try await demuxer.open()
        XCTAssertFalse(streamInfo.tracks.isEmpty)

        var previousPTS: Int64?
        var samples: [Sample] = []
        for _ in 0..<90 {
            guard let sample = try await demuxer.readSample() else { break }
            if let previousPTS {
                XCTAssertGreaterThanOrEqual(sample.ptsNanoseconds, previousPTS)
            }
            XCTAssertGreaterThanOrEqual(sample.durationNanoseconds, 0)
            previousPTS = sample.ptsNanoseconds
            samples.append(sample)
        }
        XCTAssertFalse(samples.isEmpty)

        let initSegment = try await repackager.generateInitSegment(streamInfo: streamInfo)
        let initBoxes = try BMFFSanityParser.parseTopLevel(initSegment)
        XCTAssertTrue(BMFFSanityParser.containsPath(["moov", "trak", "mdia", "minf", "stbl", "stsd"], in: initBoxes))

        let chunks = stride(from: 0, to: samples.count, by: max(1, samples.count / 5)).map {
            Array(samples[$0..<min(samples.count, $0 + max(1, samples.count / 5))])
        }
        var fragmentCount = 0
        for chunk in chunks.prefix(5) where !chunk.isEmpty {
            let fragment = try await repackager.generateFragment(samples: chunk)
            let boxes = try BMFFSanityParser.parseTopLevel(fragment)
            XCTAssertTrue(BMFFSanityParser.containsPath(["moof"], in: boxes))
            XCTAssertTrue(BMFFSanityParser.containsPath(["mdat"], in: boxes))
            fragmentCount += 1
        }
        XCTAssertGreaterThan(fragmentCount, 0)
    }
}

private final class FixtureRangeURLProtocol: URLProtocol {
    static var storage = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "fixture.local"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let data = Self.storage
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
