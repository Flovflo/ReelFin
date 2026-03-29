import PlaybackEngine
import Shared
import XCTest

final class PlaybackWarmupManagerTests: XCTestCase {
    func test_warm_deduplicatesConcurrentRequests() async {
        let recorder = WarmResolverRecorder()
        let manager = PlaybackWarmupManager(ttl: 120) { itemID in
            try await recorder.resolve(itemID: itemID)
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await manager.warm(itemID: "movie-1") }
            group.addTask { await manager.warm(itemID: "movie-1") }
            group.addTask { await manager.warm(itemID: "movie-1") }
        }

        let selection = await manager.selection(for: "movie-1")
        let callCount = await recorder.callCount

        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(selection?.source.id, "movie-1")
    }

    func test_trim_discardsFarAwayEntries() async {
        let manager = PlaybackWarmupManager(ttl: 120) { itemID in
            PlaybackAssetSelection(
                source: MediaSource(
                    id: itemID,
                    itemID: itemID,
                    name: itemID,
                    supportsDirectPlay: true,
                    supportsDirectStream: true,
                    directStreamURL: URL(string: "https://example.com/\(itemID).m3u8"),
                    directPlayURL: URL(string: "https://example.com/\(itemID).mp4"),
                    transcodeURL: URL(string: "https://example.com/\(itemID)-transcode.m3u8")
                ),
                decision: PlaybackDecision(
                    sourceID: itemID,
                    route: .directPlay(URL(string: "https://example.com/\(itemID).mp4")!)
                ),
                assetURL: URL(string: "https://example.com/\(itemID).mp4")!,
                headers: [:],
                debugInfo: PlaybackDebugInfo(
                    container: "mp4",
                    videoCodec: "h264",
                    videoBitDepth: nil,
                    hdrMode: .sdr,
                    audioMode: "aac",
                    bitrate: nil,
                    playMethod: "DirectPlay"
                )
            )
        }

        await manager.warm(itemID: "keep")
        await manager.warm(itemID: "drop")
        await manager.trim(keeping: ["keep"])
        let keptSelection = await manager.selection(for: "keep")
        let droppedSelection = await manager.selection(for: "drop")

        XCTAssertNotNil(keptSelection)
        XCTAssertNil(droppedSelection)
    }
}

private actor WarmResolverRecorder {
    private(set) var callCount = 0

    func resolve(itemID: String) async throws -> PlaybackAssetSelection {
        callCount += 1
        return PlaybackAssetSelection(
            source: MediaSource(
                id: itemID,
                itemID: itemID,
                name: itemID,
                supportsDirectPlay: true,
                supportsDirectStream: true,
                directStreamURL: URL(string: "https://example.com/\(itemID).m3u8"),
                directPlayURL: URL(string: "https://example.com/\(itemID).mp4"),
                transcodeURL: URL(string: "https://example.com/\(itemID)-transcode.m3u8")
            ),
            decision: PlaybackDecision(
                sourceID: itemID,
                route: .directPlay(URL(string: "https://example.com/\(itemID).mp4")!)
            ),
            assetURL: URL(string: "https://example.com/\(itemID).mp4")!,
            headers: [:],
            debugInfo: PlaybackDebugInfo(
                container: "mp4",
                videoCodec: "h264",
                videoBitDepth: nil,
                hdrMode: .sdr,
                audioMode: "aac",
                bitrate: nil,
                playMethod: "DirectPlay"
            )
        )
    }
}
