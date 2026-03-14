import XCTest
@testable import PlaybackEngine
@testable import Shared

final class UnifiedTrackModelTests: XCTestCase {

    // MARK: - A. Track Mapping from MediaTrack

    func testUnifiedTrack_fromMediaTrack() {
        let mediaTrack = MediaTrack(
            id: "audio-1",
            title: "English - AC3 5.1",
            language: "eng",
            codec: "ac3",
            isDefault: true,
            index: 1
        )

        let unified = UnifiedTrack.from(mediaTrack, engineSource: .server)

        XCTAssertEqual(unified.id, "audio-1")
        XCTAssertEqual(unified.title, "English - AC3 5.1")
        XCTAssertEqual(unified.language, "eng")
        XCTAssertEqual(unified.codec, "ac3")
        XCTAssertTrue(unified.isDefault)
        XCTAssertEqual(unified.index, 1)
        XCTAssertEqual(unified.engineSource, .server)
    }

    func testUnifiedTrack_fromMediaTrack_defaultEngineSource() {
        let mediaTrack = MediaTrack(
            id: "sub-1",
            title: "French",
            language: "fre",
            codec: "srt",
            isDefault: false,
            index: 0
        )

        let unified = UnifiedTrack.from(mediaTrack)
        XCTAssertEqual(unified.engineSource, .server)
    }

    // MARK: - B. Native Engine Tracks

    func testUnifiedTrack_nativeEngineSource() {
        let track = UnifiedTrack(
            id: "0",
            title: "English",
            language: "en",
            index: 0,
            engineSource: .native
        )
        XCTAssertEqual(track.engineSource, .native)
    }

    // MARK: - C. VLC Engine Tracks

    func testUnifiedTrack_vlcEngineSource() {
        let track = UnifiedTrack(
            id: "1",
            title: "Track 1",
            index: 1,
            engineSource: .vlc
        )
        XCTAssertEqual(track.engineSource, .vlc)
    }

    // MARK: - D. Equatable

    func testUnifiedTrack_equatable() {
        let a = UnifiedTrack(id: "1", title: "English", index: 0, engineSource: .native)
        let b = UnifiedTrack(id: "1", title: "English", index: 0, engineSource: .native)
        XCTAssertEqual(a, b)

        let c = UnifiedTrack(id: "2", title: "French", index: 1, engineSource: .vlc)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - E. Identifiable

    func testUnifiedTrack_identifiable() {
        let tracks = [
            UnifiedTrack(id: "0", title: "English", index: 0),
            UnifiedTrack(id: "1", title: "French", index: 1),
            UnifiedTrack(id: "2", title: "Spanish", index: 2)
        ]
        XCTAssertEqual(Set(tracks.map(\.id)).count, 3)
    }

    // MARK: - F. MediaCharacteristics from MediaSource

    func testMediaCharacteristics_fromMediaSource() {
        let source = MediaSource(
            id: "src-1",
            itemID: "item-1",
            name: "Source 1",
            container: "MKV",
            videoCodec: "HEVC",
            audioCodec: "DTS",
            bitrate: 25_000_000,
            videoBitDepth: 10,
            videoRange: "HDR",
            videoRangeType: "HDR10",
            dvProfile: nil,
            supportsDirectPlay: true,
            supportsDirectStream: true,
            requiredHTTPHeaders: [:],
            audioTracks: [],
            subtitleTracks: [
                MediaTrack(id: "s1", title: "PGS Sub", codec: "pgs", isDefault: false, index: 0)
            ]
        )

        let chars = MediaCharacteristics.from(source: source)
        XCTAssertEqual(chars.container, "mkv")
        XCTAssertEqual(chars.videoCodec, "hevc")
        XCTAssertEqual(chars.audioCodec, "dts")
        XCTAssertEqual(chars.bitDepth, 10)
        XCTAssertEqual(chars.videoRangeType, "hdr10")
        XCTAssertTrue(chars.supportsDirectPlay)
        XCTAssertTrue(chars.subtitleCodecs.contains("pgs"))
    }
}
