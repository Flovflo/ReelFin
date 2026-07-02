import Foundation
import Shared
import XCTest
@testable import PlaybackEngine

/// Pure support logic of the custom player: MIME resolution (the tvOS no-first-frame root cause),
/// external subtitle track building, and the subtitle cue pipeline.
final class CustomPlayerSupportTests: XCTestCase {

    // MARK: - MIME (tvOS device regression 2026-07-02)

    /// ffmpeg labels the WHOLE QuickTime family — including real .mp4 files — with the composite
    /// "mov,mp4,m4a,3gp,3g2,mj2" (live-probed: an actual '.mp4' carries exactly that string). The
    /// composite therefore resolves to video/mp4; only a file extension can say "QuickTime".
    func testOverrideMIMETypeCompositeContainerResolvesToMp4() {
        let source = makeSource(container: "mov,mp4,m4a,3gp,3g2,mj2", filePath: nil)
        let mime = JellyfinOriginalSourceResolver.overrideMIMEType(
            for: URL(string: "https://server/Videos/x/stream")!, source: source)
        XCTAssertEqual(mime, "video/mp4")
    }

    func testOverrideMIMETypeUsesFilePathExtensionFirst() {
        let mkv = makeSource(container: "mov,mp4", filePath: "/media/movie.mkv")
        XCTAssertEqual(
            JellyfinOriginalSourceResolver.overrideMIMEType(
                for: URL(string: "https://server/Videos/x/stream")!, source: mkv),
            "video/x-matroska")
        let mov = makeSource(container: "mov,mp4,m4a,3gp,3g2,mj2", filePath: "/media/movie.mov")
        XCTAssertEqual(
            JellyfinOriginalSourceResolver.overrideMIMEType(
                for: URL(string: "https://server/Videos/x/stream")!, source: mov),
            "video/quicktime")
        let mp4 = makeSource(container: "mov,mp4,m4a,3gp,3g2,mj2", filePath: "/media/movie.mp4")
        XCTAssertEqual(
            JellyfinOriginalSourceResolver.overrideMIMEType(
                for: URL(string: "https://server/Videos/x/stream")!, source: mp4),
            "video/mp4")
    }

    func testOverrideMIMETypePlainMp4StaysMp4() {
        let source = makeSource(container: "mp4", filePath: nil)
        let mime = JellyfinOriginalSourceResolver.overrideMIMEType(
            for: URL(string: "https://server/Videos/x/stream")!, source: source)
        XCTAssertEqual(mime, "video/mp4")
    }

    // MARK: - External subtitle tracks

    func testExternalSubtitleTracksBuildDeliveryURLsForTextFormatsOnly() {
        var source = makeSource(container: "mp4", filePath: nil)
        source.subtitleTracks = [
            MediaTrack(id: "s1", title: "Français", language: "fr", codec: "srt", isDefault: true, index: 3),
            MediaTrack(id: "s2", title: "PGS", language: "en", codec: "pgssub", isDefault: false, index: 4),
            MediaTrack(id: "s3", title: "", language: "en", codec: "subrip", isDefault: false, index: 5)
        ]
        let assetURL = URL(string: "https://server.example/Videos/item-1/stream?static=true&api_key=tok123")!
        let tracks = JellyfinOriginalSourceResolver.externalSubtitleTracks(for: source, assetURL: assetURL)

        XCTAssertEqual(tracks.count, 2, "image-based formats (PGS) cannot be text-rendered")
        XCTAssertEqual(tracks[0].label, "Français")
        XCTAssertEqual(tracks[0].url.path, "/Videos/\(source.itemID)/\(source.id)/Subtitles/3/0/Stream.srt")
        XCTAssertTrue(tracks[0].url.query?.contains("api_key=tok123") ?? false)
        XCTAssertEqual(tracks[1].label, "en", "untitled tracks fall back to their language")
    }

    // MARK: - Subtitle cue pipeline

    @MainActor
    func testSubtitleParsingAndCueLookup() throws {
        let srt = """
        1
        00:00:01,000 --> 00:00:03,500
        <i>Bonjour</i> le monde

        2
        00:00:10,000 --> 00:00:12,000
        {\\an8}Deuxième réplique
        ligne deux
        """
        let cues = try XCTUnwrap(SubtitleOverlayModel.parse(text: srt))
        XCTAssertEqual(cues.count, 2)

        let model = makeModel(with: srt)
        model.updateTime(2.0)
        XCTAssertEqual(model.currentCue, "Bonjour le monde", "markup must be stripped")
        model.updateTime(5.0)
        XCTAssertNil(model.currentCue, "gap between cues shows nothing")
        model.updateTime(11.0)
        XCTAssertEqual(model.currentCue, "Deuxième réplique\nligne deux")
        // Backwards seek restarts the cursor.
        model.updateTime(2.0)
        XCTAssertEqual(model.currentCue, "Bonjour le monde")
    }

    func testVTTTimestampParsing() {
        XCTAssertEqual(SubtitleOverlayModel.seconds(fromVTTTimestamp: "01:02:03.500"), 3_723.5)
        XCTAssertEqual(SubtitleOverlayModel.seconds(fromVTTTimestamp: "02:03.250"), 123.25)
        XCTAssertNil(SubtitleOverlayModel.seconds(fromVTTTimestamp: "garbage"))
    }

    // MARK: - Helpers

    @MainActor
    private func makeModel(with srt: String) -> SubtitleOverlayModel {
        let model = SubtitleOverlayModel()
        model.debugInstall(cuesFrom: srt)
        return model
    }

    private func makeSource(container: String?, filePath: String?) -> MediaSource {
        MediaSource(
            id: "source-1",
            itemID: "item-1",
            name: "Fixture",
            filePath: filePath,
            container: container,
            supportsDirectPlay: true,
            supportsDirectStream: true
        )
    }
}
