@testable import JellyfinAPI
import XCTest

final class MediaSourceDTOURLResolutionTests: XCTestCase {
    func testRelativeStreamURLPreservesQuery() {
        let dto = MediaSourceDTO(
            id: "source-1",
            name: "source",
            container: "mkv",
            videoCodec: "h264",
            audioCodec: "aac",
            supportsDirectPlay: true,
            supportsDirectStream: true,
            directStreamURL: "/Videos/abc/stream?Static=true&MediaSourceId=source-1",
            transcodingURL: "/Videos/abc/master.m3u8?MediaSourceId=source-1",
            mediaStreams: nil
        )

        let serverURL = URL(string: "https://jellyfin.example.com/jf")!
        let domain = dto.toDomain(itemID: "abc", serverURL: serverURL)

        XCTAssertEqual(domain.directStreamURL?.host, "jellyfin.example.com")
        XCTAssertEqual(domain.directStreamURL?.path, "/jf/Videos/abc/stream")
        XCTAssertEqual(domain.directStreamURL?.query, "Static=true&MediaSourceId=source-1")
    }

    func testAbsoluteTranscodingURLIsKept() {
        let dto = MediaSourceDTO(
            id: "source-2",
            name: "source",
            container: "mkv",
            videoCodec: "h264",
            audioCodec: "aac",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            transcodingURL: "https://cdn.example.com/master.m3u8?token=123",
            mediaStreams: nil
        )

        let serverURL = URL(string: "https://jellyfin.example.com")!
        let domain = dto.toDomain(itemID: "abc", serverURL: serverURL)

        XCTAssertEqual(domain.transcodeURL?.absoluteString, "https://cdn.example.com/master.m3u8?token=123")
    }
}
