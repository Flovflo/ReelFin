import Foundation
import NativeMediaCore
import XCTest
@testable import PlaybackEngine

final class LocalMediaGatewayHTTPRangeSecurityTests: XCTestCase {
    override func tearDown() async throws {
        MockOriginalMediaProtocol.reset()
        try await super.tearDown()
    }

    func testMultiRangeRequestIsRejectedInsteadOfBeingTreatedAsNoRange() {
        XCTAssertNil(makeRequest(range: "bytes=0-0,2-3"))
    }

    func testClosedRangeEndingAtInt64MaxIsRejectedWithoutOverflow() async throws {
        let response = try await fetchFromOrigin(range: "bytes=0-9223372036854775807", storage: byteStorage())

        XCTAssertEqual(response.statusCode, 416)
        XCTAssertEqual(response.data, Data())
        XCTAssertEqual(response.response.value(forHTTPHeaderField: "Content-Range"), "bytes */32")
    }

    func testOpenRangeStartingAtInt64MaxIsUnsatisfiable() throws {
        let request = try XCTUnwrap(makeRequest(range: "bytes=9223372036854775807-"))

        XCTAssertNil(request.range?.resolve(totalLength: 32))
    }

    func testZeroLengthSuffixIsRejectedAsMalformed() {
        XCTAssertNil(makeRequest(range: "bytes=-0"))
    }

    func testRangesWithEndpointsOutsideResourceAreUnsatisfiable() throws {
        for range in ["bytes=32-32", "bytes=33-"] {
            let request = try XCTUnwrap(makeRequest(range: range))
            XCTAssertNil(request.range?.resolve(totalLength: 32), range)
        }
    }

    func testClosedEndOutsideResourceIsRejectedByOriginGateway() async throws {
        let response = try await fetchFromOrigin(range: "bytes=0-32", storage: byteStorage())

        XCTAssertEqual(response.statusCode, 416)
        XCTAssertEqual(response.data, Data())
        XCTAssertEqual(response.response.value(forHTTPHeaderField: "Content-Range"), "bytes */32")
    }

    func testValidClosedOpenAndSuffixRangesPreserveHTTPRangeSemantics() async throws {
        for (range, expectedBytes, expectedContentRange) in [
            ("bytes=0-0", Data([0]), "bytes 0-0/32"),
            ("bytes=4-7", Data([4, 5, 6, 7]), "bytes 4-7/32"),
            ("bytes=4-", Data((4..<32).map(UInt8.init)), "bytes 4-31/32"),
            ("bytes=-4", Data((28..<32).map(UInt8.init)), "bytes 28-31/32")
        ] {
            let response = try await fetchFromOrigin(range: range, storage: byteStorage())
            XCTAssertEqual(response.statusCode, 206, range)
            XCTAssertEqual(response.data, expectedBytes, range)
            XCTAssertEqual(response.response.value(forHTTPHeaderField: "Content-Range"), expectedContentRange, range)
            XCTAssertEqual(response.response.value(forHTTPHeaderField: "Content-Length"), "\(expectedBytes.count)", range)
        }
    }

    func testValidRangeLargerThan16MiBAdvertisesAndStreamsCompleteInterval() async throws {
        let length = 16 * 1_024 * 1_024 + 1_025
        let storage = Data((0..<length).map { UInt8($0 % 251) })
        let parsed = try XCTUnwrap(makeRequest(range: "bytes=0-\(length - 1)"))
        let resolved = try XCTUnwrap(parsed.range?.resolve(totalLength: Int64(length)))
        XCTAssertEqual(resolved, LocalMediaGatewayResolvedRange(start: 0, endExclusive: Int64(length)))
        let response = try await fetchFromOrigin(range: "bytes=0-\(length - 1)", storage: storage)

        XCTAssertEqual(response.statusCode, 206)
        XCTAssertEqual(response.response.value(forHTTPHeaderField: "Content-Length"), "\(length)")
        XCTAssertEqual(response.response.value(forHTTPHeaderField: "Content-Range"), "bytes 0-\(length - 1)/\(length)")
        XCTAssertEqual(response.data.count, length)
        XCTAssertEqual(response.data.last, UInt8((length - 1) % 251))
    }

    func testSuffixLargerThanImplicitWindowStreamsCompleteTail() async throws {
        let suffixLength = 4 * 1_024 * 1_024 + 1_025
        let totalLength = suffixLength + 1_024
        let storage = Data((0..<totalLength).map { UInt8($0 % 251) })

        let response = try await fetchFromOrigin(range: "bytes=-\(suffixLength)", storage: storage)

        XCTAssertEqual(response.statusCode, 206)
        XCTAssertEqual(response.response.value(forHTTPHeaderField: "Content-Length"), "\(suffixLength)")
        XCTAssertEqual(
            response.response.value(forHTTPHeaderField: "Content-Range"),
            "bytes 1024-\(totalLength - 1)/\(totalLength)"
        )
        XCTAssertEqual(response.data, storage.subdata(in: 1_024..<totalLength))
    }

    private func makeRequest(range: String) -> LocalMediaGatewayHTTPRequest? {
        LocalMediaGatewayHTTPRequest(
            Data("GET /media/item HTTP/1.1\r\nRange: \(range)\r\n\r\n".utf8)
        )
    }

    private func byteStorage() -> Data {
        Data((0..<32).map(UInt8.init))
    }

    private func fetchFromOrigin(
        range: String,
        storage: Data
    ) async throws -> (data: Data, response: HTTPURLResponse, statusCode: Int) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalMediaGatewayHTTPRangeSecurityTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        MockOriginalMediaProtocol.storage = storage
        let store = try MediaGatewayStore(
            directoryURL: directory,
            configuration: MediaGatewayStore.Configuration(
                chunkSize: 64 * 1_024,
                maxBytes: max(storage.count * 2, 1_024)
            )
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockOriginalMediaProtocol.self]
        let session = LocalMediaGatewaySession(
            remoteURL: URL(string: "https://media.example.com/video.mp4")!,
            headers: [:],
            key: MediaGatewayCacheKey(
                scope: "range-security",
                userID: "user",
                serverID: "server",
                itemID: UUID().uuidString,
                sourceID: "source",
                routeURL: URL(string: "https://media.example.com/video.mp4")!
            ),
            store: store,
            sessionConfiguration: configuration
        )
        let server = LocalMediaGatewayServer(session: session)
        let url = try server.start()
        defer { server.stop(reason: "range_security_test_teardown") }

        var request = URLRequest(url: url)
        request.setValue(range, forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        return (data, http, http.statusCode)
    }
}
