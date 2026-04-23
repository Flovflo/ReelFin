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

    func test_warmWithResumePreheatsOncePerResumeBucket() async {
        let preheater = WarmStartupPreheaterRecorder()
        let manager = PlaybackWarmupManager(
            ttl: 120,
            resolver: { itemID in
                makeWarmPlaylistSelection(itemID: itemID)
            },
            startupPreheater: { selection, resumeSeconds, runtimeSeconds, isTVOS in
                await preheater.preheat(
                    selection: selection,
                    resumeSeconds: resumeSeconds,
                    runtimeSeconds: runtimeSeconds,
                    isTVOS: isTVOS
                )
            }
        )

        await manager.warm(itemID: "movie-1", resumeSeconds: 600, runtimeSeconds: 3_600, isTVOS: false)
        await manager.warm(itemID: "movie-1", resumeSeconds: 610, runtimeSeconds: 3_600, isTVOS: false)
        await manager.warm(itemID: "movie-1", resumeSeconds: 640, runtimeSeconds: 3_600, isTVOS: false)

        let calls = await preheater.calls
        let result = await manager.startupPreheatResult(
            for: "movie-1",
            resumeSeconds: 610,
            runtimeSeconds: 3_600,
            isTVOS: false
        )

        XCTAssertEqual(calls.map(\.resumeSeconds), [600, 640])
        XCTAssertEqual(calls.map(\.isTVOS), [false, false])
        XCTAssertEqual(result?.reason, "test_preheat")
    }
}

private actor WarmResolverRecorder {
    private(set) var callCount = 0

    func resolve(itemID: String) async throws -> PlaybackAssetSelection {
        callCount += 1
        return makeWarmSelection(itemID: itemID)
    }
}

private actor WarmStartupPreheaterRecorder {
    struct Call: Equatable {
        let itemID: String
        let resumeSeconds: Double
        let runtimeSeconds: Double?
        let isTVOS: Bool
    }

    private(set) var calls: [Call] = []

    func preheat(
        selection: PlaybackAssetSelection,
        resumeSeconds: Double,
        runtimeSeconds: Double?,
        isTVOS: Bool
    ) -> PlaybackStartupPreheater.Result {
        calls.append(
            Call(
                itemID: selection.source.itemID,
                resumeSeconds: resumeSeconds,
                runtimeSeconds: runtimeSeconds,
                isTVOS: isTVOS
            )
        )
        return PlaybackStartupPreheater.Result(
            byteCount: 1024,
            elapsedSeconds: 0.1,
            observedBitrate: 81_920,
            rangeStart: nil,
            reason: "test_preheat"
        )
    }
}

private func makeWarmSelection(itemID: String) -> PlaybackAssetSelection {
    let url = URL(string: "https://example.com/\(itemID).mp4")!
    return PlaybackAssetSelection(
        source: MediaSource(
            id: itemID,
            itemID: itemID,
            name: itemID,
            fileSize: 4_000_000_000,
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            bitrate: 8_000_000,
            supportsDirectPlay: true,
            supportsDirectStream: true,
            directStreamURL: URL(string: "https://example.com/\(itemID).m3u8"),
            directPlayURL: url,
            transcodeURL: URL(string: "https://example.com/\(itemID)-transcode.m3u8")
        ),
        decision: PlaybackDecision(
            sourceID: itemID,
            route: .directPlay(url)
        ),
        assetURL: url,
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

private func makeWarmPlaylistSelection(itemID: String) -> PlaybackAssetSelection {
    let url = URL(string: "https://example.com/\(itemID).m3u8")!
    return PlaybackAssetSelection(
        source: MediaSource(
            id: itemID,
            itemID: itemID,
            name: itemID,
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            bitrate: 12_000_000,
            supportsDirectPlay: true,
            supportsDirectStream: true,
            directStreamURL: url,
            directPlayURL: url,
            transcodeURL: URL(string: "https://example.com/\(itemID)-transcode.m3u8")
        ),
        decision: PlaybackDecision(
            sourceID: itemID,
            route: .directPlay(url)
        ),
        assetURL: url,
        headers: [:],
        debugInfo: PlaybackDebugInfo(
            container: "mp4",
            videoCodec: "h264",
            videoBitDepth: nil,
            hdrMode: .sdr,
            audioMode: "aac",
            bitrate: 12_000_000,
            playMethod: "DirectPlay"
        )
    )
}
