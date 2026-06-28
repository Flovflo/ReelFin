@testable import PlaybackEngine
import Shared
import XCTest

/// Offline proof for the custom player's "prefer the MP4 twin over the MKV" source selection
/// (`PlaybackCoordinator.preferringContainers`). An MKV stalls the contiguous localhost cache via
/// AVKit's index seeks; a progressive MP4 reads linearly. This is the deterministic, no-device test
/// that the right source is chosen (and that MKV-only titles are never made unplayable).
final class PlaybackCoordinatorContainerPrefTests: XCTestCase {

    private func source(id: String, path: String?, container: String?) -> MediaSource {
        MediaSource(
            id: id,
            itemID: "item",
            name: id,
            filePath: path,
            container: container,
            videoCodec: "hevc",
            audioCodec: "eac3",
            supportsDirectPlay: true,
            supportsDirectStream: true,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: nil
        )
    }

    func testPrefersMP4TwinOverMKV() {
        let mkv = source(id: "mkv", path: "/media/Show/S01E01.H265-FW.mkv", container: "mkv")
        let mp4 = source(id: "mp4", path: "/media/Show/S01E01.H265-FW.mp4", container: "mp4")
        let kept = PlaybackCoordinator.preferringContainers([mkv, mp4], ["mp4", "m4v", "mov"], itemID: "item")
        XCTAssertEqual(kept.map(\.id), ["mp4"], "Must keep only the MP4 source when preferring MP4-class containers.")
    }

    func testFilePathExtensionIsAuthoritativeOverContainerField() {
        // The Container field can be a device-profile list ("mov,mp4,…"); the real file is MKV.
        let mkv = source(id: "mkv", path: "/media/x.mkv", container: "mov,mp4,m4a,3gp,3g2,mj2")
        let mp4 = source(id: "mp4", path: "/media/x.mp4", container: "mov,mp4,m4a,3gp,3g2,mj2")
        let kept = PlaybackCoordinator.preferringContainers([mkv, mp4], ["mp4"], itemID: "item")
        XCTAssertEqual(kept.map(\.id), ["mp4"], "Path extension must decide, not the negotiated container list.")
    }

    func testMKVOnlyTitleIsLeftUnchanged() {
        let mkv = source(id: "mkv", path: "/media/x.mkv", container: "mkv")
        let kept = PlaybackCoordinator.preferringContainers([mkv], ["mp4", "m4v", "mov"], itemID: "item")
        XCTAssertEqual(kept.map(\.id), ["mkv"], "An MKV-only title must stay playable (no filtering to empty).")
    }

    func testNoPreferenceIsANoOp() {
        let mkv = source(id: "mkv", path: "/media/x.mkv", container: "mkv")
        let mp4 = source(id: "mp4", path: "/media/x.mp4", container: "mp4")
        XCTAssertEqual(PlaybackCoordinator.preferringContainers([mkv, mp4], nil, itemID: "item").map(\.id), ["mkv", "mp4"])
        XCTAssertEqual(PlaybackCoordinator.preferringContainers([mkv, mp4], [], itemID: "item").map(\.id), ["mkv", "mp4"])
    }

    func testAllSourcesAlreadyPreferredIsUnchanged() {
        let a = source(id: "a", path: "/media/a.mp4", container: "mp4")
        let b = source(id: "b", path: "/media/b.mp4", container: "mp4")
        let kept = PlaybackCoordinator.preferringContainers([a, b], ["mp4"], itemID: "item")
        XCTAssertEqual(kept.map(\.id), ["a", "b"], "When everything already matches, keep them all (no spurious narrowing).")
    }

    func testContainerFieldFallbackWhenNoFilePath() {
        let mkv = source(id: "mkv", path: nil, container: "mkv")
        let mp4 = source(id: "mp4", path: nil, container: "mp4")
        let kept = PlaybackCoordinator.preferringContainers([mkv, mp4], ["mp4"], itemID: "item")
        XCTAssertEqual(kept.map(\.id), ["mp4"], "With no Path, fall back to the Container field.")
    }
}
