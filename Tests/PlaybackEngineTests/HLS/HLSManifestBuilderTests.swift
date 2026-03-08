@testable import PlaybackEngine
import XCTest

final class HLSManifestBuilderTests: XCTestCase {
    func testMasterPlaylistMatchesExpectedExactContent() {
        let builder = HLSManifestBuilder()
        let master = builder.makeMasterPlaylist(
            videoPlaylistURI: "video.m3u8",
            codecs: "hvc1.2.4.L153.B0,ec-3",
            supplementalCodecs: nil,
            videoRange: "PQ",
            resolution: "3840x1608",
            bandwidth: 20_000_000
        )

        let expected = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-STREAM-INF:BANDWIDTH=20000000,CODECS="hvc1.2.4.L153.B0,ec-3",VIDEO-RANGE=PQ,RESOLUTION=3840x1608
        video.m3u8

        """

        XCTAssertEqual(master, expected)
    }

    func testMediaPlaylistMatchesExpectedExactContent() {
        let builder = HLSManifestBuilder()
        let media = builder.makeMediaPlaylist(
            targetDuration: 3,
            mediaSequence: 0,
            initSegmentURI: "init.mp4",
            segments: [
                HLSMediaPlaylistSegment(uri: "segment_0.m4s", duration: 1.519),
                HLSMediaPlaylistSegment(uri: "segment_1.m4s", duration: 3.000)
            ],
            endList: false
        )

        let expected = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:3
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-PLAYLIST-TYPE:EVENT
        #EXT-X-MAP:URI="init.mp4"
        #EXTINF:1.519,
        segment_0.m4s
        #EXTINF:3.000,
        segment_1.m4s

        """

        XCTAssertEqual(media, expected)
    }

    func testMasterPlaylistIncludesVideoRangeAndSupplementalCodecs() {
        let builder = HLSManifestBuilder()
        let master = builder.makeMasterPlaylist(
            videoPlaylistURI: "video.m3u8",
            codecs: "hvc1.2.4.L153.B0,ec-3",
            supplementalCodecs: "dvh1.08.06/db1p",
            videoRange: "PQ",
            resolution: "3840x1608",
            bandwidth: 20_000_000
        )

        XCTAssertTrue(master.contains("#EXTM3U"))
        XCTAssertTrue(master.contains("#EXT-X-VERSION:7"))
        XCTAssertTrue(master.contains("CODECS=\"hvc1.2.4.L153.B0,ec-3\""))
        XCTAssertTrue(master.contains("VIDEO-RANGE=PQ"))
        XCTAssertTrue(master.contains("SUPPLEMENTAL-CODECS=\"dvh1.08.06/db1p\""))
        XCTAssertTrue(master.contains("RESOLUTION=3840x1608"))
        XCTAssertTrue(master.contains("video.m3u8"))
    }

    func testMediaPlaylistIncludesMapAndIndependentSegments() {
        let builder = HLSManifestBuilder()
        let media = builder.makeMediaPlaylist(
            targetDuration: 3,
            mediaSequence: 0,
            initSegmentURI: "init.mp4",
            segments: [
                HLSMediaPlaylistSegment(uri: "segment_0.m4s", duration: 1.500),
                HLSMediaPlaylistSegment(uri: "segment_1.m4s", duration: 2.000)
            ],
            endList: false
        )

        XCTAssertTrue(media.contains("#EXTM3U"))
        XCTAssertTrue(media.contains("#EXT-X-TARGETDURATION:3"))
        XCTAssertTrue(media.contains("#EXT-X-MAP:URI=\"init.mp4\""))
        XCTAssertTrue(media.contains("#EXT-X-INDEPENDENT-SEGMENTS"))
        XCTAssertTrue(media.contains("#EXTINF:1.500,"))
        XCTAssertTrue(media.contains("segment_0.m4s"))
        XCTAssertTrue(media.contains("#EXTINF:2.000,"))
        XCTAssertTrue(media.contains("segment_1.m4s"))
    }
}
