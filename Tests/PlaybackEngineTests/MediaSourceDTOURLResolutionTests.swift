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

    func testVideoMetadataMapsDolbyVisionAndColorFields() {
        let stream = MediaStreamDTO(
            index: 0,
            type: "Video",
            title: nil,
            displayTitle: "HEVC DV",
            language: nil,
            isDefault: true,
            codec: "hevc",
            profile: "Main 10",
            bitDepth: 10,
            colorRange: "tv",
            colorSpace: "bt2020nc",
            colorTransfer: "smpte2084",
            colorPrimaries: "bt2020",
            dvVersionMajor: 1,
            dvVersionMinor: 0,
            dvProfile: 8,
            dvLevel: 6,
            rpuPresentFlag: true,
            elPresentFlag: false,
            blPresentFlag: true,
            dvBlSignalCompatibilityId: 1,
            hdr10PlusPresentFlag: false,
            videoRange: "HDR",
            videoRangeType: "DOVIWithHDR10",
            videoDoViTitle: "Dolby Vision",
            channels: nil,
            channelLayout: nil,
            bitrate: 15_000_000,
            width: 3840,
            height: 1608
        )
        let dto = MediaSourceDTO(
            id: "source-3",
            name: "dv",
            container: "mkv",
            videoCodec: nil,
            audioCodec: "eac3",
            supportsDirectPlay: true,
            supportsDirectStream: true,
            directStreamURL: "/Videos/abc/stream?Static=true",
            transcodingURL: nil,
            mediaStreams: [stream]
        )

        let domain = dto.toDomain(itemID: "abc", serverURL: URL(string: "https://jellyfin.example.com")!)
        XCTAssertEqual(domain.videoRangeType, "DOVIWithHDR10")
        XCTAssertEqual(domain.dvProfile, 8)
        XCTAssertEqual(domain.dvLevel, 6)
        XCTAssertEqual(domain.dvBlSignalCompatibilityId, 1)
        XCTAssertEqual(domain.colorTransfer, "smpte2084")
        XCTAssertEqual(domain.colorPrimaries, "bt2020")
    }
}
