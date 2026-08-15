@testable import PlaybackEngine
import CoreMedia
import Foundation
import XCTest

private let validSyntheticTestHVCC = Data([
    0x01, 0x22, 0x20, 0x00, 0x00, 0x00,
    0x90, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x99, 0xF0, 0x00, 0xFC, 0xFD, 0xFA,
    0xFA, 0x00, 0x00, 0x0F, 0x03,
    0xA0, 0x00, 0x01, 0x00, 0x02, 0x40, 0x01,
    0xA1, 0x00, 0x01, 0x00, 0x02, 0x42, 0x01,
    0xA2, 0x00, 0x01, 0x00, 0x02, 0x44, 0x01
])

final class SyntheticHLSSessionTests: XCTestCase {
    func testSessionBuildsPlaylistsAndSegments() async throws {
        let samples = makeSamples(count: 80)
        let demuxer = MockDemuxer(samples: samples)
        let repackager = MockRepackager()
        let plan = makePlan()
        let session = SyntheticHLSSession(plan: plan, demuxer: demuxer, repackager: repackager)

        try await session.prepare()
        let master = try await session.masterPlaylist()
        let media = try await session.mediaPlaylist(preloadCount: 2)
        let initSegment = try await session.initSegment()
        let segment0 = try await session.segment(sequence: 0)

        XCTAssertTrue(master.contains("#EXTM3U"))
        XCTAssertTrue(media.contains("#EXT-X-MAP"))
        XCTAssertFalse(initSegment.isEmpty)
        XCTAssertFalse(segment0.isEmpty)
    }

    func testMasterPlaylistUsesPlannedVideoTrackResolutionInMultiVideoStream() async throws {
        let unselectedPrimary = TrackInfo(
            id: 10,
            trackType: .video,
            codecID: "V_MPEGH/ISO/HEVC",
            codecName: "hevc",
            isDefault: true,
            width: 3840,
            height: 2160,
            bitDepth: 10,
            codecPrivate: validSyntheticTestHVCC
        )
        let selectedVideo = TrackInfo(
            id: 20,
            trackType: .video,
            codecID: "V_MPEGH/ISO/HEVC",
            codecName: "hevc",
            isDefault: false,
            width: 640,
            height: 360,
            bitDepth: 10,
            codecPrivate: validSyntheticTestHVCC
        )
        let plan = NativeBridgePlan(
            itemID: "selected-resolution",
            sourceID: "selected-resolution-source",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: selectedVideo,
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "SDR",
            whyChosen: "selected-resolution-test"
        )
        let frameDuration = CMTime(value: 1, timescale: 24)
        var samples: [Sample] = []
        for index in 0..<80 {
            samples.append(Sample(
                trackID: selectedVideo.id,
                pts: CMTime(value: CMTimeValue(index), timescale: 24),
                duration: frameDuration,
                isKeyframe: index % 24 == 0,
                data: Data([UInt8(index & 0xFF), 0x01])
            ))
        }
        let demuxer = MultiTrackDemuxer(
            tracks: [unselectedPrimary, selectedVideo],
            samples: samples
        )
        let session = SyntheticHLSSession(
            plan: plan,
            demuxer: demuxer,
            repackager: MockRepackager()
        )

        try await session.prepare()
        let master = try await session.masterPlaylist()

        XCTAssertTrue(master.contains("RESOLUTION=640x360"))
        XCTAssertFalse(master.contains("RESOLUTION=3840x2160"))
    }

    func testPrepareRejectsMalformedHEVCBeforeRepackaging() async throws {
        let malformedTrack = TrackInfo(
            id: 1,
            trackType: .video,
            codecID: "V_MPEGH/ISO/HEVC",
            codecName: "hevc",
            isDefault: true,
            width: 1920,
            height: 1080,
            bitDepth: 10,
            codecPrivate: Data(validSyntheticTestHVCC.prefix(23))
        )
        let plan = NativeBridgePlan(
            itemID: "malformed-hevc",
            sourceID: "malformed-hevc-source",
            sourceURL: URL(string: "https://example.com/malformed.mkv")!,
            videoTrack: malformedTrack,
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "SDR",
            whyChosen: "malformed-hvcc-test"
        )
        let demuxer = SingleTrackDemuxer(track: malformedTrack, samples: makeSamples(count: 8))
        let repackager = RecordingRepackager()
        let session = SyntheticHLSSession(plan: plan, demuxer: demuxer, repackager: repackager)

        do {
            try await session.prepare()
            XCTFail("Malformed HEVC configuration must fail before init/segment generation.")
        } catch let error as SyntheticHLSError {
            XCTAssertEqual(error.errorDescription, "Unsupported HEVC decoder configuration")
        }
        let generatedFragmentCount = await repackager.generatedFragmentCount()
        let generatedInitCount = await repackager.generatedInitCount()
        XCTAssertEqual(generatedFragmentCount, 0)
        XCTAssertEqual(generatedInitCount, 0)
    }

    func testPrepareRejectsIncompleteHVC1BeforeInitOrFragmentGeneration() async throws {
        let incompleteHVC1 = Data([
            0x01, 0x22, 0x20, 0x00, 0x00, 0x00,
            0x90, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x99, 0xF0, 0x00, 0xFC, 0xFD, 0xFA,
            0xFA, 0x00, 0x00, 0x0F, 0x01,
            0xA0, 0x00, 0x01, 0x00, 0x02, 0x40, 0x01
        ])
        let videoTrack = TrackInfo(
            id: 1,
            trackType: .video,
            codecID: "hvc1",
            codecName: "hvc1",
            isDefault: true,
            width: 1920,
            height: 1080,
            bitDepth: 10,
            codecPrivate: incompleteHVC1
        )
        let plan = NativeBridgePlan(
            itemID: "incomplete-hvc1",
            sourceID: "incomplete-hvc1-source",
            sourceURL: URL(string: "https://example.com/incomplete.mkv")!,
            videoTrack: videoTrack,
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "SDR",
            whyChosen: "incomplete-hvc1-test"
        )
        let demuxer = SingleTrackDemuxer(track: videoTrack, samples: makeSamples(count: 8))
        let repackager = RecordingRepackager()
        let session = SyntheticHLSSession(plan: plan, demuxer: demuxer, repackager: repackager)

        do {
            try await session.prepare()
            XCTFail("Incomplete hvc1 parameter sets must fail before init/fragment generation.")
        } catch let error as SyntheticHLSError {
            XCTAssertEqual(error.errorDescription, "Unsupported HEVC decoder configuration")
        }
        let generatedInitCount = await repackager.generatedInitCount()
        let generatedFragmentCount = await repackager.generatedFragmentCount()
        XCTAssertEqual(generatedInitCount, 0)
        XCTAssertEqual(generatedFragmentCount, 0)
    }

    func testSeekInvalidationResetsCacheAndScheduler() async throws {
        let samples = makeSamples(count: 120)
        let demuxer = MockDemuxer(samples: samples)
        let repackager = MockRepackager()
        let session = SyntheticHLSSession(plan: makePlan(), demuxer: demuxer, repackager: repackager)

        try await session.prepare()
        _ = try await session.mediaPlaylist()
        _ = try await waitForGeneratedSegmentCount(in: session, atLeast: 2)
        _ = try await session.mediaPlaylist()
        let before = try await session.advertisedSegment(sequence: 1)
        XCTAssertFalse(before.isEmpty)

        try await session.invalidateForSeek(targetPTS: 0)
        _ = try await session.mediaPlaylist(startupPreflightSnapshot: true)
        let after = try await session.advertisedSegment(sequence: 0)
        XCTAssertFalse(after.isEmpty)
    }

    func testPublishedSnapshotRemainsReadableUntilNextPlaylistUnderCountAndBytePressure() async throws {
        let cache = SegmentCacheActor(maxBytes: 18, maxSegments: 3)
        let repackager = SizedRepackager(fragmentSizes: [2, 8, 8, 8])
        let playlistCommitBarrier = GenerationCommitBarrier()
        let session = SyntheticHLSSession(
            plan: makePlan(),
            demuxer: MockDemuxer(samples: makeSamples(count: 1_200)),
            repackager: repackager,
            cache: cache,
            defaultPreloadCount: 3
        )

        try await session.prepare()
        _ = try await session.mediaPlaylist()
        let snapshot = try await session.mediaPlaylist()
        let snapshotSequences = playlistSegmentSequences(in: snapshot)
        XCTAssertEqual(snapshotSequences, [0, 1, 2])
        await session.setBeforePlaylistCommitHookForTesting {
            await playlistCommitBarrier.pause()
        }

        let refreshTask = Task { try await session.mediaPlaylist() }
        await playlistCommitBarrier.waitUntilEntered()

        for sequence in snapshotSequences {
            let bytes = try await session.advertisedSegment(sequence: sequence)
            XCTAssertFalse(
                bytes.isEmpty,
                "Every URI in snapshot N must stay servable until snapshot N+1 returns."
            )
        }

        await playlistCommitBarrier.release()
        let nextSnapshot = try await refreshTask.value
        await session.setBeforePlaylistCommitHookForTesting(nil)
        let nextSequences = playlistSegmentSequences(in: nextSnapshot)
        XCTAssertEqual(nextSequences, [2])
        for sequence in snapshotSequences where !nextSequences.contains(sequence) {
            do {
                _ = try await session.advertisedSegment(sequence: sequence)
                XCTFail("A URI removed by returned snapshot N+1 must no longer be advertised.")
            } catch let error as SyntheticHLSError {
                XCTAssertEqual(
                    error.errorDescription,
                    SyntheticHLSError.missingSegment(sequence).errorDescription
                )
            }
        }
    }

    func testConcurrentPlaylistRefreshesOwnPublicationAndDrainAdmittedReaders() async throws {
        let cache = SegmentCacheActor(maxBytes: 18, maxSegments: 3)
        let repackager = SizedRepackager(fragmentSizes: [2, 8, 8, 8, 8])
        let admittedReaderBarrier = GenerationCommitBarrier()
        let publicationBarrier = GenerationCommitBarrier()
        let ordering = PublicationOrderingProbe()
        let session = SyntheticHLSSession(
            plan: makePlan(),
            demuxer: MockDemuxer(samples: makeSamples(count: 1_200)),
            repackager: repackager,
            cache: cache,
            defaultPreloadCount: 3
        )

        try await session.prepare()
        _ = try await session.mediaPlaylist()
        let snapshot = try await session.mediaPlaylist()
        XCTAssertEqual(playlistSegmentSequences(in: snapshot), [0, 1, 2])

        await cache.setBeforeAdvertisedEntryHookForTesting {
            await ordering.record(.readerLookupEntered)
            await admittedReaderBarrier.pause()
            await ordering.record(.readerLookupReleased)
        }
        await session.setDuringPlaylistCommitHookForTesting {
            await ordering.record(.publicationCommitEntered)
            await publicationBarrier.pause()
        }

        let admittedReader = Task { try await session.advertisedSegment(sequence: 0) }
        await admittedReaderBarrier.waitUntilEntered()

        let firstRefresh = Task { try await session.mediaPlaylist() }
        await session.waitForPlaylistPublicationForTesting()
        let secondRefresh = Task { try await session.mediaPlaylist() }
        await session.waitForPlaylistOperationWaiterCountForTesting(1)

        await admittedReaderBarrier.release()
        let admittedBytes = try await admittedReader.value
        XCTAssertFalse(admittedBytes.isEmpty)
        await publicationBarrier.waitUntilEntered()

        let retainedReader = Task { try await session.advertisedSegment(sequence: 2) }
        await session.waitForAdvertisedSegmentWaiterCountForTesting(1)
        let operationWaiterCount = await session.playlistOperationWaiterCountForTesting()
        XCTAssertEqual(operationWaiterCount, 1)

        await publicationBarrier.release()
        let firstPlaylist = try await firstRefresh.value
        let retainedBytes = try await retainedReader.value
        XCTAssertFalse(retainedBytes.isEmpty)
        let secondPlaylist = try await secondRefresh.value

        for playlist in [firstPlaylist, secondPlaylist] {
            let sequences = playlistSegmentSequences(in: playlist)
            if let first = sequences.first, let last = sequences.last {
                XCTAssertEqual(sequences, Array(first...last))
            }
        }
        let events = await ordering.events()
        let readerReleaseIndex = try XCTUnwrap(events.firstIndex(of: .readerLookupReleased))
        let commitIndex = try XCTUnwrap(events.firstIndex(of: .publicationCommitEntered))
        XCTAssertLessThan(
            readerReleaseIndex,
            commitIndex,
            "A reader admitted under snapshot N must finish its cache lookup before publication can commit N+1."
        )

        await cache.setBeforeAdvertisedEntryHookForTesting(nil)
        await session.setDuringPlaylistCommitHookForTesting(nil)
        try await session.invalidateForSeek(targetPTS: 0)
        _ = try await session.mediaPlaylist(startupPreflightSnapshot: true)
        let postSeekBytes = try await session.advertisedSegment(sequence: 0)
        XCTAssertFalse(postSeekBytes.isEmpty)
    }

    func testConcurrentRefreshesAndSeekQueueBehindOneOwnedPlaylistOperation() async throws {
        let session = SyntheticHLSSession(
            plan: makePlan(),
            demuxer: MockDemuxer(samples: makeSamples(count: 1_200)),
            repackager: RecordingRepackager()
        )
        let commitBarrier = GenerationCommitBarrier()
        let transitions = PlaylistOperationTransitionProbe()

        try await session.prepare()
        _ = try await session.mediaPlaylist()
        await session.setPlaylistOperationTransitionHookForTesting { transition in
            await transitions.record(transition)
        }
        await session.setBeforePlaylistCommitHookForTesting {
            await commitBarrier.pause()
        }

        let firstRefresh = Task { try await session.mediaPlaylist() }
        await commitBarrier.waitUntilEntered()
        let secondRefresh = Task { try await session.mediaPlaylist() }
        let seek = Task { try await session.invalidateForSeek(targetPTS: 0) }
        await transitions.waitUntilCount(3)

        let initialTransitions = Array(await transitions.events().prefix(3))
        XCTAssertEqual(initialTransitions, [.acquired, .queued, .queued])

        await commitBarrier.release()
        _ = await firstRefresh.result
        _ = await secondRefresh.result
        _ = await seek.result
        await session.setBeforePlaylistCommitHookForTesting(nil)
        await session.setPlaylistOperationTransitionHookForTesting(nil)

        try await session.invalidateForSeek(targetPTS: 0)
        let postSeekPlaylist = try await session.mediaPlaylist(startupPreflightSnapshot: true)
        XCTAssertEqual(playlistSegmentSequences(in: postSeekPlaylist), [0])
    }

    func testByteSaturatedWorkingSetPublishesContiguousWindowsWithoutTerminalError() async throws {
        let cache = SegmentCacheActor(maxBytes: 10, maxSegments: 12)
        let repackager = SizedRepackager(fragmentSizes: Array(repeating: 4, count: 8))
        let session = SyntheticHLSSession(
            plan: makePlan(),
            demuxer: MockDemuxer(samples: makeSamples(count: 1_200)),
            repackager: repackager,
            cache: cache,
            defaultPreloadCount: 3
        )

        try await session.prepare()
        let snapshotN = try await session.mediaPlaylist()
        _ = try await repackager.waitForFragmentCount(2)
        let snapshotN1 = try await session.mediaPlaylist()
        _ = try await repackager.waitForFragmentCount(3)
        let snapshotN2 = try await session.mediaPlaylist()

        XCTAssertEqual(playlistSegmentSequences(in: snapshotN), [0, 1])
        XCTAssertEqual(playlistSegmentSequences(in: snapshotN1), [1])
        XCTAssertEqual(playlistSegmentSequences(in: snapshotN2), [1, 2])
        for snapshot in [snapshotN, snapshotN1, snapshotN2] {
            let advertised = playlistSegmentSequences(in: snapshot)
            let first = try XCTUnwrap(advertised.first)
            let last = try XCTUnwrap(advertised.last)
            XCTAssertEqual(advertised, Array(first...last))
        }
        let latest = try await session.advertisedSegment(sequence: 2)
        XCTAssertFalse(latest.isEmpty)
    }

    func testBytePressureNeverEvictsTheUnpublishedImmediatePredecessor() async throws {
        let cache = SegmentCacheActor(maxBytes: 10, maxSegments: 12)
        try await cache.put(Data(repeating: 0x00, count: 4), duration: 1, for: 0)
        _ = await cache.advertiseRetained()
        try await cache.put(Data(repeating: 0x01, count: 4), duration: 1, for: 1)

        do {
            try await cache.put(Data(repeating: 0x02, count: 4), duration: 1, for: 2)
            XCTFail("Insertion must fail transactionally instead of evicting the sequential reserve predecessor.")
        } catch let error as SyntheticHLSError {
            guard case .workingSetCapacityExhausted(sequence: 2) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let retained = await cache.retainedEntries().map(\.sequence)
        XCTAssertEqual(retained, [0, 1])
    }

    func testVariableFragmentSizesPublishEverySequenceInFIFOOrder() async throws {
        let (session, repackager, cache) = makeVariableSizePressureSession()

        try await session.prepare()
        var publicationOrder: [Int] = []
        var nextExpectedSequence = 0
        for cycle in 0...3 {
            let playlist = try await session.mediaPlaylist()
            let advertised = playlistSegmentSequences(in: playlist)
            let first = try XCTUnwrap(advertised.first)
            let last = try XCTUnwrap(advertised.last)
            XCTAssertEqual(advertised, Array(first...last))
            for sequence in advertised where sequence >= nextExpectedSequence {
                XCTAssertEqual(sequence, nextExpectedSequence)
                publicationOrder.append(sequence)
                nextExpectedSequence += 1
            }

            if cycle < 3 {
                _ = try await repackager.waitForFragmentCount(cycle + 2)
                let retainedNextSequence = try await waitForRetainedSequence(cycle + 1, in: cache)
                XCTAssertTrue(retainedNextSequence)
                for sequence in advertised {
                    let snapshotBytes = try await session.advertisedSegment(sequence: sequence)
                    XCTAssertFalse(snapshotBytes.isEmpty, "Snapshot N must stay readable while its one FIFO reserve is generated.")
                }
            }
        }

        XCTAssertEqual(Array(publicationOrder.prefix(4)), [0, 1, 2, 3])
    }

    func testPromotedPrefetchKeepsVariableFragmentsFIFOAndSingleStaged() async throws {
        let (session, _, cache) = makeVariableSizePressureSession()

        try await session.prepare()
        var publicationOrder: [Int] = []
        var nextExpectedSequence = 0
        for cycle in 0...3 {
            let playlist = try await session.mediaPlaylist()
            await session.promotePrefetch(preloadCount: 12, lookaheadSegments: 12)
            let advertised = playlistSegmentSequences(in: playlist)
            let first = try XCTUnwrap(advertised.first)
            let last = try XCTUnwrap(advertised.last)
            XCTAssertEqual(advertised, Array(first...last))
            for sequence in advertised where sequence >= nextExpectedSequence {
                XCTAssertEqual(sequence, nextExpectedSequence)
                publicationOrder.append(sequence)
                nextExpectedSequence += 1
            }

            if cycle < 3 {
                let retained = await cache.retainedEntries()
                let stagedFuture = retained.filter {
                    !$0.isAdvertised && $0.sequence > (advertised.last ?? -1)
                }
                XCTAssertLessThanOrEqual(
                    stagedFuture.count,
                    1,
                    "Promotion must never stage more than one unknown-size successor."
                )
                for sequence in advertised {
                    let snapshotBytes = try await session.advertisedSegment(sequence: sequence)
                    XCTAssertFalse(snapshotBytes.isEmpty)
                }
            }
        }

        XCTAssertEqual(Array(publicationOrder.prefix(4)), [0, 1, 2, 3])
    }

    func testPromotionCannotExtendAnInFlightUnknownSizeInsertion() async throws {
        let (session, _, cache) = makeVariableSizePressureSession()
        let commitBarrier = GenerationCommitBarrier()

        try await session.prepare()
        _ = try await session.mediaPlaylist()
        await session.setBeforeCacheCommitHookForTesting { sequence in
            guard sequence == 2 else { return }
            await commitBarrier.pause()
        }

        await session.promotePrefetch(preloadCount: 12, lookaheadSegments: 12)
        await commitBarrier.waitUntilEntered()
        await session.promotePrefetch(preloadCount: 12, lookaheadSegments: 12)
        await commitBarrier.release()
        await session.waitForPrefetchForTesting()

        let playlist = try await session.mediaPlaylist()
        let advertised = playlistSegmentSequences(in: playlist)
        let first = try XCTUnwrap(advertised.first)
        let last = try XCTUnwrap(advertised.last)
        XCTAssertEqual(advertised, Array(first...last))
        XCTAssertTrue(advertised.contains(2))
        let retained = await cache.retainedEntries()
        XCTAssertLessThanOrEqual(retained.filter { !$0.isAdvertised }.count, 1)
    }

    func testWorkingSetPublishesDataDurationAndAdvertisementAtomically() async throws {
        let cache = SegmentCacheActor(maxBytes: 15, maxSegments: 3)
        try await cache.put(Data(repeating: 0xA0, count: 4), duration: 1.25, for: 0)
        try await cache.put(Data(repeating: 0xB1, count: 5), duration: 2.5, for: 1)

        let firstAdvertisement = await cache.advertiseRetained()
        XCTAssertEqual(firstAdvertisement.map(\.sequence), [0, 1])
        XCTAssertEqual(firstAdvertisement.map(\.duration), [1.25, 2.5])

        try await cache.put(Data(repeating: 0xC2, count: 6), duration: 3.75, for: 2)
        let retained = await cache.retainedEntries()
        let firstStillAdvertised = await cache.advertisedEntry(for: 0)
        let stillAdvertised = await cache.advertisedEntry(for: 1)
        let unadvertisedPrefetch = await cache.advertisedEntry(for: 2)

        XCTAssertEqual(retained.map(\.sequence), [0, 1, 2])
        XCTAssertEqual(retained.reduce(0) { $0 + $1.data.count }, 15)
        XCTAssertEqual(firstStillAdvertised?.duration, 1.25)
        XCTAssertEqual(stillAdvertised?.duration, 2.5)
        XCTAssertNil(unadvertisedPrefetch, "A prefetched fragment is not HTTP-readable until a playlist advertises it.")
    }

    func testWorkingSetRejectsSingleOversizeFragmentWithoutRetainingMetadata() async throws {
        let cache = SegmentCacheActor(maxBytes: 8, maxSegments: 3)

        do {
            try await cache.put(Data(repeating: 0xFF, count: 9), duration: 1, for: 0)
            XCTFail("A fragment larger than the whole byte budget must fail closed.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("working set"))
        }

        let retained = await cache.retainedEntries()
        XCTAssertTrue(retained.isEmpty)
    }

    func testOversizePrefetchFailsClosedWithoutAdvertisingSequenceGap() async throws {
        let cache = SegmentCacheActor(maxBytes: 8, maxSegments: 3)
        let repackager = SizedRepackager(fragmentSizes: [4, 9])
        let session = SyntheticHLSSession(
            plan: makePlan(),
            demuxer: MockDemuxer(samples: makeSamples(count: 240)),
            repackager: repackager,
            cache: cache
        )

        try await session.prepare()
        do {
            _ = try await session.mediaPlaylist()
            XCTFail("A failed oversize prefetch must not let the playlist skip that sequence.")
        } catch let error as SyntheticHLSError {
            XCTAssertTrue(error.localizedDescription.contains("working set"))
        }
        let retained = await cache.retainedEntries()
        XCTAssertEqual(retained.map(\.sequence), [0])
    }

    func testAdvertisedSegmentRereadDoesNotDemuxOrRepackageAgain() async throws {
        let demuxer = MockDemuxer(samples: makeSamples(count: 240))
        let repackager = RecordingRepackager()
        let session = SyntheticHLSSession(plan: makePlan(), demuxer: demuxer, repackager: repackager)

        try await session.prepare()
        _ = try await session.mediaPlaylist(startupPreflightSnapshot: true)
        let beforeReads = await demuxer.sampleReadCount()
        let beforeFragments = await repackager.generatedFragmentCount()

        let first = try await session.advertisedSegment(sequence: 0)
        let second = try await session.advertisedSegment(sequence: 0)
        let afterReads = await demuxer.sampleReadCount()
        let afterFragments = await repackager.generatedFragmentCount()

        XCTAssertEqual(first, second)
        XCTAssertEqual(afterReads, beforeReads)
        XCTAssertEqual(afterFragments, beforeFragments)
    }

    func testPlaylistAdvertisesExactlyTheRetainedWindowUnderPressure() async throws {
        let cache = SegmentCacheActor(maxBytes: 64, maxSegments: 2)
        let repackager = RecordingRepackager()
        let session = SyntheticHLSSession(
            plan: makePlan(),
            demuxer: MockDemuxer(samples: makeSamples(count: 720)),
            repackager: repackager,
            cache: cache,
            defaultPreloadCount: 3
        )

        try await session.prepare()
        _ = try await session.mediaPlaylist()
        let generatedFragmentCount = try await waitForGeneratedFragmentCount(in: repackager, atLeast: 2)
        let playlist = try await session.mediaPlaylist(startupPreflightSnapshot: true)
        let retainedEntries = await cache.retainedEntries()
        let retained = retainedEntries.map(\.sequence)
        let advertised = playlistSegmentSequences(in: playlist)

        XCTAssertLessThanOrEqual(retained.count, 2)
        XCTAssertEqual(generatedFragmentCount, 2, "Prefetch must stop at the retained segment window.")
        XCTAssertLessThanOrEqual(retainedEntries.reduce(0) { $0 + $1.data.count }, 64)
        XCTAssertEqual(advertised, Array(retained.prefix(1)))
    }

    func testFullWorkingSetSlidesForwardOnPlaylistRefreshWithoutExceedingBudget() async throws {
        let cache = SegmentCacheActor(maxBytes: 64, maxSegments: 3)
        let repackager = RecordingRepackager()
        let demuxer = FreezeableDemuxer(samples: makeSamples(count: 1_200))
        let session = SyntheticHLSSession(
            plan: makePlan(),
            demuxer: demuxer,
            repackager: repackager,
            cache: cache,
            defaultPreloadCount: 3
        )

        try await session.prepare()
        _ = try await session.mediaPlaylist()
        let startupCount = try await waitForGeneratedFragmentCount(in: repackager, atLeast: 2)
        XCTAssertEqual(startupCount, 2)
        let retainedSequenceOne = try await waitForRetainedSequence(1, in: cache)
        XCTAssertTrue(retainedSequenceOne)

        _ = try await session.mediaPlaylist()
        let middleCount = try await waitForGeneratedFragmentCount(in: repackager, atLeast: 3)
        XCTAssertEqual(middleCount, 3)
        let retainedSequenceTwo = try await waitForRetainedSequence(2, in: cache)
        XCTAssertTrue(retainedSequenceTwo)

        _ = try await session.mediaPlaylist()
        let advancedCount = try await waitForGeneratedFragmentCount(in: repackager, atLeast: 4)
        XCTAssertEqual(advancedCount, 4)
        let retainedSequenceThree = try await waitForRetainedSequence(3, in: cache)
        XCTAssertTrue(retainedSequenceThree)
        await demuxer.freezeReads()
        let advancedPlaylist = try await session.mediaPlaylist(startupPreflightSnapshot: false)
        let retained = await cache.retainedEntries()

        XCTAssertEqual(retained.map(\.sequence), [1, 2, 3])
        XCTAssertLessThanOrEqual(retained.reduce(0) { $0 + $1.data.count }, 64)
        XCTAssertEqual(playlistSegmentSequences(in: advancedPlaylist), [1, 2, 3])
        XCTAssertTrue(advancedPlaylist.contains("#EXT-X-MEDIA-SEQUENCE:1"))

        do {
            _ = try await session.advertisedSegment(sequence: 0)
            XCTFail("An evicted segment must not be regenerated by an HTTP-style reread.")
        } catch let error as SyntheticHLSError {
            XCTAssertEqual(error.errorDescription, SyntheticHLSError.missingSegment(0).errorDescription)
        }
        let fragmentCountAfterEvictedReread = await repackager.generatedFragmentCount()
        XCTAssertEqual(fragmentCountAfterEvictedReread, advancedCount)
    }

    func testSlidingPlaylistOmitsEventAndKeepsTargetDurationStableAcrossWindowRefreshes() async throws {
        let cache = SegmentCacheActor(maxBytes: 256, maxSegments: 3)
        let repackager = RecordingRepackager()
        let session = SyntheticHLSSession(
            plan: makePlan(),
            demuxer: MockDemuxer(samples: makeSamples(count: 2_400)),
            repackager: repackager,
            cache: cache,
            defaultPreloadCount: 3
        )

        try await session.prepare()
        var playlists: [String] = []
        for _ in 0..<6 {
            playlists.append(try await session.mediaPlaylist())
            await session.waitForPrefetchForTesting()
        }
        playlists.append(try await session.mediaPlaylist())

        let targets = playlists.compactMap(targetDuration(in:))
        XCTAssertEqual(targets.count, playlists.count)
        XCTAssertEqual(Set(targets).count, 1, "TARGETDURATION must remain stable for the whole generation.")
        XCTAssertTrue(playlists.allSatisfy { !$0.contains("#EXT-X-PLAYLIST-TYPE:EVENT") })
        XCTAssertGreaterThan(playlistMediaSequence(in: playlists.last ?? ""), 0)
    }

    func testConcurrentSchedulerRequestsCannotInterleaveDemuxOrRepackageSameSequence() async throws {
        let demuxer = DelayedReadDemuxer(samples: makeSamples(count: 240))
        let repackager = RecordingRepackager()
        let scheduler = PackagingSchedulerActor(
            demuxer: demuxer,
            repackager: repackager,
            videoTrackID: 1,
            targetDurationSeconds: 3
        )

        let first = Task { try await scheduler.segment(for: 0) }
        try await demuxer.waitForActiveRead()
        let second = Task { try await scheduler.segment(for: 0) }
        let firstResult = await first.result
        let secondResult = await second.result
        let successCount = [firstResult, secondResult].reduce(into: 0) { count, result in
            if case .success = result { count += 1 }
        }

        XCTAssertEqual(successCount, 1)
        let peakReads = await demuxer.maximumConcurrentReads()
        let fragmentCount = await repackager.generatedFragmentCount()
        XCTAssertEqual(peakReads, 1)
        XCTAssertEqual(fragmentCount, 1)
    }

    func testSeekCancelsAndAwaitsOwnedPrefetchBeforeTouchingDemuxer() async throws {
        let demuxer = SeekRaceDemuxer(samples: makeSamples(count: 600))
        let session = SyntheticHLSSession(
            plan: makePlan(),
            demuxer: demuxer,
            repackager: RecordingRepackager()
        )

        try await session.prepare()
        await demuxer.delaySubsequentRead()
        let playlistTask = Task { try await session.mediaPlaylist() }
        try await demuxer.waitForDelayedRead()
        try await session.invalidateForSeek(targetPTS: 0)
        _ = await playlistTask.result

        let seekRacedRead = await demuxer.seekBeganDuringDelayedRead()
        XCTAssertFalse(
            seekRacedRead,
            "Seek/reset must cancel and await the only owned generation task before mutating demux state."
        )
        let playlist = try await session.mediaPlaylist(startupPreflightSnapshot: true)
        XCTAssertEqual(playlistSegmentSequences(in: playlist), [0])
    }

    func testConcurrentPlaylistRefreshesSerializeAndOwnOnePrefetchTask() async throws {
        let demuxer = DelayedReadDemuxer(samples: makeSamples(count: 600))
        let repackager = RecordingRepackager()
        let session = SyntheticHLSSession(plan: makePlan(), demuxer: demuxer, repackager: repackager)

        try await session.prepare()
        async let first = session.mediaPlaylist()
        async let second = session.mediaPlaylist()
        _ = try await (first, second)
        _ = try await waitForGeneratedFragmentCount(in: repackager, atLeast: 2)

        let peakReads = await demuxer.maximumConcurrentReads()
        let fragmentCount = await repackager.generatedFragmentCount()
        XCTAssertEqual(peakReads, 1)
        XCTAssertEqual(
            fragmentCount,
            3,
            "The queued refresh may advance once after the first completes, but generation stays single-flight."
        )
    }

    func testSeekClearsAdvertisementAndBackwardSeekRebuildsStartupWindow() async throws {
        let demuxer = MockDemuxer(samples: makeSamples(count: 240))
        let repackager = RecordingRepackager()
        let session = SyntheticHLSSession(plan: makePlan(), demuxer: demuxer, repackager: repackager)

        try await session.prepare()
        _ = try await session.mediaPlaylist(startupPreflightSnapshot: true)
        let beforeSeek = try await session.advertisedSegment(sequence: 0)
        XCTAssertFalse(beforeSeek.isEmpty)

        try await session.invalidateForSeek(targetPTS: 0)
        do {
            _ = try await session.advertisedSegment(sequence: 0)
            XCTFail("A segment from the previous generation must not remain advertised after seek.")
        } catch let error as SyntheticHLSError {
            XCTAssertEqual(error.errorDescription, SyntheticHLSError.missingSegment(0).errorDescription)
        }

        let rebuiltPlaylist = try await session.mediaPlaylist(startupPreflightSnapshot: true)
        let rebuiltSegment = try await session.advertisedSegment(sequence: 0)
        let fragmentCount = await repackager.generatedFragmentCount()
        XCTAssertEqual(playlistSegmentSequences(in: rebuiltPlaylist), [0])
        XCTAssertFalse(rebuiltSegment.isEmpty)
        XCTAssertEqual(fragmentCount, 2)
    }

    func testMediaPlaylistReturnsQuicklyWithoutSyncGeneratingExtraSegments() async throws {
        let samples = makeSamples(count: 240)
        let demuxer = FreezeableDemuxer(samples: samples)
        let repackager = MockRepackager()
        let session = SyntheticHLSSession(plan: makePlan(), demuxer: demuxer, repackager: repackager)

        try await session.prepare()
        await demuxer.freezeReads()

        let started = Date()
        let media = try await session.mediaPlaylist(preloadCount: 3)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertTrue(media.contains("#EXTM3U"))
        XCTAssertTrue(media.contains("segment_0.m4s"))
        XCTAssertLessThan(elapsed, 1.0, "mediaPlaylist() should return quickly from already generated state.")
    }

    func testLongGOPWithoutBoundaryWithinBudgetFailsWithoutAdvertisingSegment() async throws {
        let samples = makeSamples(count: 720, keyframeInterval: 320)
        let demuxer = MockDemuxer(samples: samples)
        let repackager = RecordingRepackager()
        let session = SyntheticHLSSession(plan: makePlan(), demuxer: demuxer, repackager: repackager)

        var rejected = false
        do {
            try await session.prepare()
            XCTFail("A startup GOP beyond the explicit search budget must be rejected.")
        } catch {
            rejected = true
            XCTAssertTrue(error.localizedDescription.contains("Independent segment boundary unavailable"))
        }
        guard rejected else { return }

        let readCount = await demuxer.sampleReadCount()
        let fragmentCount = await repackager.generatedFragmentCount()
        let generatedCount = await session.generatedSequenceCountForTesting()
        XCTAssertLessThanOrEqual(readCount, 289, "The 12-second duration budget must bound a long GOP before its 320th frame.")
        XCTAssertEqual(fragmentCount, 0)
        XCTAssertEqual(generatedCount, 0)
        do {
            _ = try await session.mediaPlaylist()
            XCTFail("A rejected prepare must not expose a media playlist.")
        } catch let error as SyntheticHLSError {
            XCTAssertEqual(error.errorDescription, SyntheticHLSError.notPrepared.errorDescription)
        }
    }

    func testNoKeyframeSearchIsBoundedAndGeneratesNoFragment() async throws {
        let samples = makeSamples(count: 240, keyframeInterval: 1).map { sample in
            Sample(
                trackID: sample.trackID,
                pts: sample.pts,
                duration: sample.duration,
                isKeyframe: false,
                data: sample.data
            )
        }
        let demuxer = MockDemuxer(samples: samples)
        let repackager = RecordingRepackager()
        let scheduler = PackagingSchedulerActor(
            demuxer: demuxer,
            repackager: repackager,
            videoTrackID: 1,
            startupMaxSamples: 16
        )

        do {
            _ = try await scheduler.segment(for: 0)
            XCTFail("Missing random-access point must fail within the configured budget.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Independent segment boundary unavailable"))
        }

        let readCount = await demuxer.sampleReadCount()
        let fragmentCount = await repackager.generatedFragmentCount()
        let generatedSequences = await scheduler.generatedSequences()
        XCTAssertLessThanOrEqual(readCount, 16)
        XCTAssertEqual(fragmentCount, 0)
        XCTAssertTrue(generatedSequences.isEmpty)
    }

    func testUnselectedTrackFloodStillConsumesBoundedDemuxReadBudget() async throws {
        let samples = (0..<240).map { index in
            Sample(
                trackID: 99,
                pts: CMTime(value: Int64(index), timescale: 30),
                duration: CMTime(value: 1, timescale: 30),
                isKeyframe: true,
                data: Data([0x99, UInt8(index & 0xFF)])
            )
        }
        let demuxer = MockDemuxer(samples: samples)
        let repackager = RecordingRepackager()
        let scheduler = PackagingSchedulerActor(
            demuxer: demuxer,
            repackager: repackager,
            videoTrackID: 1,
            startupMaxSamples: 16
        )

        do {
            _ = try await scheduler.segment(for: 0)
            XCTFail("Unselected packets must not bypass every independent-boundary budget.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Independent segment boundary unavailable"))
        }

        let readCount = await demuxer.sampleReadCount()
        let fragmentCount = await repackager.generatedFragmentCount()
        XCTAssertLessThanOrEqual(readCount, 64)
        XCTAssertEqual(fragmentCount, 0)
    }

    func testShortEOFWithoutVideoSyncRejectsAudioOnlyFragment() async throws {
        var samples = (0..<8).map { index in
            Sample(
                trackID: 1,
                pts: CMTime(value: Int64(index), timescale: 30),
                duration: CMTime(value: 1, timescale: 30),
                isKeyframe: false,
                data: Data([0x11, UInt8(index)])
            )
        }
        samples.append(
            Sample(
                trackID: 2,
                pts: .zero,
                duration: CMTime(value: 1, timescale: 30),
                isKeyframe: true,
                data: Data([0x22, 0x01])
            )
        )
        let demuxer = MockDemuxer(samples: samples)
        let repackager = RecordingRepackager()
        let scheduler = PackagingSchedulerActor(
            demuxer: demuxer,
            repackager: repackager,
            videoTrackID: 1,
            audioTrackID: 2
        )

        do {
            _ = try await scheduler.segment(for: 0)
            XCTFail("EOF without a video random-access sample must not advertise audio-only media.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Independent segment boundary unavailable"))
        }
        let fragmentCount = await repackager.generatedFragmentCount()
        XCTAssertEqual(fragmentCount, 0)
    }

    func testDefaultBoundaryBudgetAcceptsSixtyFPSVideoWithInterleavedAudio() async throws {
        let videoFrameNs: Int64 = 16_666_667
        let audioFrameNs: Int64 = 21_333_333
        var samples: [Sample] = (0..<240).map { index in
            Sample(
                trackID: 1,
                pts: CMTime(value: Int64(index) * videoFrameNs, timescale: 1_000_000_000),
                duration: CMTime(value: videoFrameNs, timescale: 1_000_000_000),
                isKeyframe: index.isMultiple(of: 120),
                data: Data([0x11, UInt8(index & 0xFF)])
            )
        }
        samples.append(contentsOf: (0..<188).map { index in
            Sample(
                trackID: 2,
                pts: CMTime(value: Int64(index) * audioFrameNs, timescale: 1_000_000_000),
                duration: CMTime(value: audioFrameNs, timescale: 1_000_000_000),
                isKeyframe: true,
                data: Data([0x22, UInt8(index & 0xFF)])
            )
        })
        samples.sort { $0.ptsNanoseconds < $1.ptsNanoseconds }

        let demuxer = MockDemuxer(samples: samples)
        let repackager = RecordingRepackager()
        let scheduler = PackagingSchedulerActor(
            demuxer: demuxer,
            repackager: repackager,
            videoTrackID: 1,
            audioTrackID: 2
        )

        _ = try await scheduler.segment(for: 0)
        _ = try await scheduler.segment(for: 1)

        let first = await repackager.samples(forGeneratedFragmentAt: 0)
        let second = await repackager.samples(forGeneratedFragmentAt: 1)
        XCTAssertTrue(first.contains(where: { $0.trackID == 2 }))
        XCTAssertEqual(second.first(where: { $0.trackID == 1 })?.isKeyframe, true)
    }

    func testPublicBoundaryParametersAreClampedWithoutOverflow() async throws {
        let demuxer = MockDemuxer(samples: [])
        let scheduler = PackagingSchedulerActor(
            demuxer: demuxer,
            repackager: RecordingRepackager(),
            videoTrackID: 1,
            audioTrackID: 2,
            targetDurationSeconds: .infinity,
            startupTargetDurationSeconds: .nan,
            startupMaxSamples: .max,
            maximumSegmentBytes: .max,
            maximumBoundarySearchDurationSeconds: .infinity
        )

        do {
            _ = try await scheduler.segment(for: 0)
            XCTFail("An empty demux must terminate without trapping on public boundary parameters.")
        } catch let error as SyntheticHLSError {
            XCTAssertEqual(error.errorDescription, SyntheticHLSError.endOfStream.errorDescription)
        }
    }

    func testEveryAdvertisedSegmentStartsWithIndependentVideoSyncSample() async throws {
        let samples = makeSamples(count: 360, keyframeInterval: 48)
        let demuxer = FreezeableDemuxer(samples: samples)
        let plan = makePlan()
        let repackager = FMP4Repackager(plan: plan)
        let session = SyntheticHLSSession(plan: plan, demuxer: demuxer, repackager: repackager)

        try await session.prepare()
        _ = try await session.mediaPlaylist(preloadCount: 3)
        _ = try await waitForGeneratedSegmentCount(in: session, atLeast: 2)
        _ = try await session.mediaPlaylist(preloadCount: 3)
        _ = try await waitForGeneratedSegmentCount(in: session, atLeast: 3)
        await demuxer.freezeReads()
        let playlist = try await session.mediaPlaylist(preloadCount: 3)
        let advertisedSequences = playlist
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> Int? in
                guard line.hasPrefix("segment_"), line.hasSuffix(".m4s") else { return nil }
                return Int(line.dropFirst("segment_".count).dropLast(".m4s".count))
            }
        XCTAssertEqual(advertisedSequences, [0, 1, 2])

        for sequence in advertisedSequences {
            let fragment = try await session.advertisedSegment(sequence: sequence)
            XCTAssertEqual(
                try firstSampleFlags(in: fragment),
                0x02000000,
                "Advertised segment \(sequence) must independently begin with a sync video sample."
            )
        }
    }

    func testGenerationEpochDropsLeadingDependentVideoSamplesBeforeAdvertisingSegment() async throws {
        let frameNs: Int64 = 41_708_333
        var samples: [Sample] = []
        for index in 0..<120 {
            let pts = CMTime(value: Int64(index) * frameNs, timescale: 1_000_000_000)
            let duration = CMTime(value: frameNs, timescale: 1_000_000_000)
            samples.append(Sample(
                trackID: 1,
                pts: pts,
                duration: duration,
                isKeyframe: index >= 3 && (index - 3).isMultiple(of: 48),
                data: Data([UInt8(index & 0xFF), 0x01, 0x02])
            ))
        }
        let demuxer = MockDemuxer(samples: samples)
        let plan = makePlan()
        let session = SyntheticHLSSession(
            plan: plan,
            demuxer: demuxer,
            repackager: FMP4Repackager(plan: plan)
        )

        try await session.prepare()
        let playlist = try await session.mediaPlaylist(startupPreflightSnapshot: true)
        let firstFragment = try await session.segment(sequence: 0)

        XCTAssertTrue(playlist.contains("#EXT-X-INDEPENDENT-SEGMENTS"))
        XCTAssertTrue(playlist.contains("segment_0.m4s"))
        XCTAssertEqual(try firstSampleFlags(in: firstFragment), 0x02000000)
    }

    func testStartupSegmentIncludesAudioWhenAudioTrackIsConfigured() async throws {
        let samples = makeInterleavedAVSamples()
        let demuxer = MockDemuxer(samples: samples)
        let repackager = RecordingRepackager()
        let session = SyntheticHLSSession(plan: makePlan(), demuxer: demuxer, repackager: repackager)

        try await session.prepare()
        _ = try await session.mediaPlaylist(startupPreflightSnapshot: true)

        let firstFragmentTrackIDs = await repackager.trackIDs(forGeneratedFragmentAt: 0)
        XCTAssertTrue(firstFragmentTrackIDs.contains(1), "Startup fragment must include video samples.")
        XCTAssertTrue(firstFragmentTrackIDs.contains(2), "Startup fragment should include at least one audio sample when audio is selected.")
    }

    func testStartupDefersEarlyBoundaryUntilAudioAndUsesLaterSyncBoundary() async throws {
        let frameNs: Int64 = 100_000_000
        var samples: [Sample] = (0..<21).map { index in
            Sample(
                trackID: 1,
                pts: CMTime(value: Int64(index) * frameNs, timescale: 1_000_000_000),
                duration: CMTime(value: frameNs, timescale: 1_000_000_000),
                isKeyframe: index.isMultiple(of: 5),
                data: Data([0x11, UInt8(index)])
            )
        }
        samples.append(
            Sample(
                trackID: 99,
                pts: CMTime(value: 250_000_000, timescale: 1_000_000_000),
                duration: CMTime(value: 2_000_000_000, timescale: 1_000_000_000),
                isKeyframe: true,
                data: Data([0x99, 0x01])
            )
        )
        samples.append(
            Sample(
                trackID: 2,
                pts: CMTime(value: 650_000_000, timescale: 1_000_000_000),
                duration: CMTime(value: frameNs, timescale: 1_000_000_000),
                isKeyframe: true,
                data: Data([0x22, 0x01])
            )
        )
        let videoTrack = TrackInfo(
            id: 1,
            trackType: .video,
            codecID: "V_MPEGH/ISO/HEVC",
            codecName: "hevc",
            isDefault: true,
            codecPrivate: validSyntheticTestHVCC
        )
        let audioTrack = TrackInfo(
            id: 2,
            trackType: .audio,
            codecID: "A_EAC3",
            codecName: "eac3",
            isDefault: true
        )
        let demuxer = MultiTrackDemuxer(tracks: [videoTrack, audioTrack], samples: samples)
        let repackager = RecordingRepackager()
        let scheduler = PackagingSchedulerActor(
            demuxer: demuxer,
            repackager: repackager,
            videoTrackID: 1,
            audioTrackID: 2,
            targetDurationSeconds: 1,
            startupTargetDurationSeconds: 0.5,
            startupMaxSamples: 32
        )

        _ = try await scheduler.segment(for: 0)
        _ = try await scheduler.segment(for: 1)

        let first = await repackager.samples(forGeneratedFragmentAt: 0)
        let second = await repackager.samples(forGeneratedFragmentAt: 1)
        XCTAssertTrue(first.contains(where: { $0.trackID == 2 }))
        XCTAssertEqual(second.first(where: { $0.trackID == 1 })?.isKeyframe, true)
        let latestFirstPTS = first.map(\.ptsNanoseconds).max() ?? Int64.max
        let earliestSecondPTS = second.map(\.ptsNanoseconds).min() ?? Int64.min
        XCTAssertLessThan(
            latestFirstPTS,
            earliestSecondPTS,
            "The later sync boundary must keep adjacent segments timestamp-ordered."
        )
    }

    func testStartupPreflightSnapshotMediaPlaylistIsVODWithEndList() async throws {
        let samples = makeSamples(count: 80)
        let demuxer = MockDemuxer(samples: samples)
        let repackager = MockRepackager()
        let session = SyntheticHLSSession(plan: makePlan(), demuxer: demuxer, repackager: repackager)

        try await session.prepare()
        let media = try await session.mediaPlaylist(preloadCount: 3, startupPreflightSnapshot: true)

        XCTAssertTrue(media.contains("#EXT-X-PLAYLIST-TYPE:VOD"))
        XCTAssertTrue(media.contains("#EXT-X-ENDLIST"))
        XCTAssertEqual(
            media.split(whereSeparator: \.isNewline).filter { $0.contains("segment_") }.count,
            1,
            "Startup preflight snapshot must advertise only the first media segment."
        )
    }

    func testPromotePrefetchExpandsGeneratedSegmentWindow() async throws {
        let samples = makeSamples(count: 1_200)
        let demuxer = MockDemuxer(samples: samples)
        let repackager = MockRepackager()
        let session = SyntheticHLSSession(
            plan: makePlan(),
            demuxer: demuxer,
            repackager: repackager,
            defaultPreloadCount: 4
        )

        try await session.prepare()
        _ = try await session.mediaPlaylist()
        var promotedCount = try await waitForGeneratedSegmentCount(in: session, atLeast: 2)
        for expectedCount in 3...10 {
            _ = try await session.mediaPlaylist()
            await session.promotePrefetch(preloadCount: 10, lookaheadSegments: 6)
            promotedCount = try await waitForGeneratedSegmentCount(
                in: session,
                atLeast: expectedCount
            )
        }
        XCTAssertGreaterThanOrEqual(promotedCount, 10)
    }

    // MARK: - Packaging Mode Tests

    /// Mode A: DV Profile 8.1 backward-compatible — hvc1 entry + dvcC + SUPPLEMENTAL-CODECS
    func testDVProfile81Compatible_producesBackwardCompatibleSignaling() async throws {
        let (plan, videoTrack, audioTrack) = makeDVProfile8PlanWithAudio()
        let demuxer = MultiTrackDemuxer(
            tracks: [videoTrack, audioTrack],
            samples: makeDVAVSamples()
        )
        let repackager = FMP4Repackager(plan: plan)
        let session = SyntheticHLSSession(
            plan: plan, demuxer: demuxer, repackager: repackager,
            packagingMode: .dvProfile81Compatible
        )

        try await session.prepare()
        let master = try await session.masterPlaylist()
        let initSegment = try await session.initSegment()
        let initNodes = try BMFFInspector.inspect(initSegment)
        let initTypes = flattenBMFFTypes(initNodes)

        // HLS signaling: backward-compatible hvc1 CODECS + SUPPLEMENTAL-CODECS for DV
        XCTAssertTrue(master.contains("CODECS=\"hvc1.2.4.H153.90,ec-3\""), "Mode A must derive hvc1 CODECS from hvcC, got: \(master)")
        XCTAssertTrue(master.contains("SUPPLEMENTAL-CODECS=\"dvh1.08.06/db1p\""), "Mode A must emit SUPPLEMENTAL-CODECS, got: \(master)")
        XCTAssertTrue(master.contains("VIDEO-RANGE=PQ"), "Mode A must signal PQ video range")

        // Init segment: hvc1 sample entry with dvcC inside (backward-compatible DV)
        XCTAssertTrue(initTypes.contains("hvc1"), "Mode A init must have hvc1 sample entry")
        XCTAssertFalse(initTypes.contains("dvh1"), "Mode A init must NOT have dvh1 sample entry")
        XCTAssertTrue(initTypes.contains("dvcC"), "Mode A init must include dvcC box")
    }

    /// Mode B: Pure HDR10 fallback — no DV boxes, no SUPPLEMENTAL-CODECS
    func testHDR10OnlyFallback_stripsAllDVSignaling() async throws {
        let videoTrack = TrackInfo(
            id: 1,
            trackType: .video,
            codecID: "V_MPEGH/ISO/HEVC",
            codecName: "hevc",
            isDefault: true,
            width: 3840,
            height: 1608,
            bitDepth: 10,
            codecPrivate: validSyntheticTestHVCC,
            colourPrimaries: 9,
            transferCharacteristic: 16,
            matrixCoefficients: 9
        )
        let plan = NativeBridgePlan(
            itemID: "dv-item",
            sourceID: "dv-source",
            sourceURL: URL(string: "https://example.com/dv.mkv")!,
            videoTrack: videoTrack,
            audioTrack: nil,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "DOVIWithHDR10",
            dvProfile: 8,
            dvLevel: 6,
            dvBlSignalCompatibilityId: 1,
            whyChosen: "integration-dv-p8-hdr10-fallback"
        )
        let demuxer = SingleTrackDemuxer(track: videoTrack, samples: [
            Sample(
                trackID: 1,
                pts: CMTime(value: 0, timescale: 1_000_000_000),
                duration: CMTime(value: 41_708_333, timescale: 1_000_000_000),
                isKeyframe: true,
                data: Data([
                    0x00, 0x00, 0x00, 0x02, 0x46, 0x01,
                    0x00, 0x00, 0x00, 0x03, 0x40, 0x01, 0x0C,
                    0x00, 0x00, 0x00, 0x03, 0x42, 0x01, 0x01,
                    0x00, 0x00, 0x00, 0x03, 0x44, 0x01, 0xC0,
                    0x00, 0x00, 0x00, 0x04, 0x28, 0x01, 0xAA, 0xBB,
                    0x00, 0x00, 0x00, 0x04, 0x7C, 0x01, 0x11, 0x22
                ])
            )
        ])
        let repackager = FMP4Repackager(plan: plan)
        let session = SyntheticHLSSession(
            plan: plan, demuxer: demuxer, repackager: repackager,
            packagingMode: .hdr10OnlyFallback
        )

        try await session.prepare()
        let master = try await session.masterPlaylist()
        let initSegment = try await session.initSegment()
        let initNodes = try BMFFInspector.inspect(initSegment)
        let initTypes = flattenBMFFTypes(initNodes)

        // HLS signaling: pure HDR10
        XCTAssertTrue(master.contains("CODECS=\"hvc1.2.4.H153.90\""), "Mode B must derive hvc1 CODECS without audio, got: \(master)")
        XCTAssertTrue(master.contains("VIDEO-RANGE=PQ"), "Mode B must signal PQ video range")
        XCTAssertFalse(master.contains("SUPPLEMENTAL-CODECS"), "Mode B must NOT emit SUPPLEMENTAL-CODECS")
        XCTAssertFalse(master.lowercased().contains("dvh1"), "Mode B must NOT reference dvh1 anywhere")

        // Init segment: clean hvc1 with no DV boxes
        XCTAssertTrue(initTypes.contains("hvc1"), "Mode B init must have hvc1 sample entry")
        XCTAssertFalse(initTypes.contains("dvh1"), "Mode B init must NOT have dvh1")
        XCTAssertFalse(initTypes.contains("dvcC"), "Mode B init must NOT include dvcC")
    }

    /// Mode C: Primary DV experimental — dvh1 entry + dvcC, CODECS=dvh1.PP.LL
    func testPrimaryDolbyVision_producesExperimentalDVSignaling() async throws {
        let (plan, videoTrack, audioTrack) = makeDVProfile8PlanWithAudio()
        let demuxer = MultiTrackDemuxer(
            tracks: [videoTrack, audioTrack],
            samples: makeDVAVSamples()
        )
        let repackager = FMP4Repackager(plan: plan)
        let session = SyntheticHLSSession(
            plan: plan, demuxer: demuxer, repackager: repackager,
            packagingMode: .primaryDolbyVisionExperimental
        )

        try await session.prepare()
        let master = try await session.masterPlaylist()
        let initSegment = try await session.initSegment()
        let initNodes = try BMFFInspector.inspect(initSegment)
        let initTypes = flattenBMFFTypes(initNodes)

        // HLS signaling: primary DV
        XCTAssertTrue(master.contains("CODECS=\"dvh1.08.06,ec-3\""), "Mode C must use dvh1 CODECS, got: \(master)")
        XCTAssertTrue(master.contains("VIDEO-RANGE=PQ"), "Mode C must signal PQ video range")
        XCTAssertFalse(master.contains("SUPPLEMENTAL-CODECS"), "Mode C must NOT emit SUPPLEMENTAL-CODECS")

        // Init segment: dvh1 sample entry with dvcC
        XCTAssertTrue(initTypes.contains("dvh1"), "Mode C init must have dvh1 sample entry")
        XCTAssertTrue(initTypes.contains("dvcC"), "Mode C init must include dvcC box")
    }

    private func makeSamples(count: Int, keyframeInterval: Int = 24) -> [Sample] {
        let frameNs: Int64 = 41_708_333
        var output: [Sample] = []
        output.reserveCapacity(count)
        let safeKeyframeInterval = max(1, keyframeInterval)
        for idx in 0..<count {
            let ptsValue = Int64(idx) * frameNs
            let sample = Sample(
                trackID: 1,
                pts: CMTime(value: ptsValue, timescale: 1_000_000_000),
                duration: CMTime(value: frameNs, timescale: 1_000_000_000),
                isKeyframe: idx % safeKeyframeInterval == 0,
                data: Data([UInt8(idx % 255), 0x01, 0x02])
            )
            output.append(sample)
        }
        return output
    }

    private func waitForGeneratedSegmentCount(
        in session: SyntheticHLSSession,
        atLeast minimumCount: Int,
        attempts: Int = 150
    ) async throws -> Int {
        for _ in 0..<attempts {
            let count = await session.generatedSequenceCountForTesting()
            if count >= minimumCount {
                return count
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        return await session.generatedSequenceCountForTesting()
    }

    private func waitForGeneratedFragmentCount(
        in repackager: RecordingRepackager,
        atLeast minimumCount: Int,
        attempts: Int = 150
    ) async throws -> Int {
        for _ in 0..<attempts {
            let count = await repackager.generatedFragmentCount()
            if count >= minimumCount { return count }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return await repackager.generatedFragmentCount()
    }

    private func playlistSegmentSequences(in playlist: String) -> [Int] {
        playlist
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> Int? in
                guard line.hasPrefix("segment_"), line.hasSuffix(".m4s") else { return nil }
                return Int(line.dropFirst("segment_".count).dropLast(".m4s".count))
            }
    }

    private func targetDuration(in playlist: String) -> Int? {
        playlist.split(whereSeparator: \.isNewline).compactMap { line in
            guard line.hasPrefix("#EXT-X-TARGETDURATION:") else { return nil }
            return Int(line.dropFirst("#EXT-X-TARGETDURATION:".count))
        }.first
    }

    private func playlistMediaSequence(in playlist: String) -> Int {
        playlist.split(whereSeparator: \.isNewline).compactMap { line in
            guard line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") else { return nil }
            return Int(line.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count))
        }.first ?? 0
    }

    private func makeInterleavedAVSamples() -> [Sample] {
        let videoFrameNs: Int64 = 41_708_333
        let audioFrameNs: Int64 = 32_000_000
        var output: [Sample] = []

        // Emit a short run of video-only packets first, then interleave audio.
        for idx in 0..<24 {
            let ptsValue = Int64(idx) * videoFrameNs
            output.append(
                Sample(
                    trackID: 1,
                    pts: CMTime(value: ptsValue, timescale: 1_000_000_000),
                    duration: CMTime(value: videoFrameNs, timescale: 1_000_000_000),
                    isKeyframe: idx % 24 == 0,
                    data: Data([0x11, UInt8(idx & 0xFF)])
                )
            )
        }

        for idx in 0..<80 {
            let videoPTS = Int64(idx + 24) * videoFrameNs
            output.append(
                Sample(
                    trackID: 1,
                    pts: CMTime(value: videoPTS, timescale: 1_000_000_000),
                    duration: CMTime(value: videoFrameNs, timescale: 1_000_000_000),
                    isKeyframe: (idx + 24) % 24 == 0,
                    data: Data([0x22, UInt8(idx & 0xFF)])
                )
            )

            let audioPTS = Int64(idx) * audioFrameNs
            output.append(
                Sample(
                    trackID: 2,
                    pts: CMTime(value: audioPTS, timescale: 1_000_000_000),
                    duration: CMTime(value: audioFrameNs, timescale: 1_000_000_000),
                    isKeyframe: true,
                    data: Data([0x33, UInt8(idx & 0xFF), 0x44])
                )
            )
        }

        return output.sorted { lhs, rhs in
            if lhs.ptsNanoseconds == rhs.ptsNanoseconds {
                return lhs.trackID < rhs.trackID
            }
            return lhs.ptsNanoseconds < rhs.ptsNanoseconds
        }
    }

    private func makePlan() -> NativeBridgePlan {
        NativeBridgePlan(
            itemID: "item",
            sourceID: "source",
            sourceURL: URL(string: "https://example.com/video.mkv")!,
            videoTrack: TrackInfo(id: 1, trackType: .video, codecID: "V_MPEGH/ISO/HEVC", codecName: "hevc", isDefault: true),
            audioTrack: TrackInfo(id: 2, trackType: .audio, codecID: "A_EAC3", codecName: "eac3", isDefault: true),
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "HDR10",
            whyChosen: "test"
        )
    }

    private func makeVariableSizePressureSession() -> (
        session: SyntheticHLSSession,
        repackager: SizedRepackager,
        cache: SegmentCacheActor
    ) {
        let repackager = SizedRepackager(fragmentSizes: [2, 8, 8, 8, 8])
        let cache = SegmentCacheActor(maxBytes: 18, maxSegments: 3)
        let session = SyntheticHLSSession(
            plan: makePlan(),
            demuxer: MockDemuxer(samples: makeSamples(count: 1_500)),
            repackager: repackager,
            cache: cache,
            defaultPreloadCount: 3
        )
        return (session, repackager, cache)
    }

    private func waitForRetainedSequence(
        _ sequence: Int,
        in cache: SegmentCacheActor,
        attempts: Int = 150
    ) async throws -> Bool {
        for _ in 0..<attempts {
            if await cache.retainedEntries().contains(where: { $0.sequence == sequence }) {
                return true
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return false
    }

    private func firstEXTINFDuration(in playlist: String) -> Double? {
        for line in playlist.split(whereSeparator: \.isNewline).map(String.init) where line.hasPrefix("#EXTINF:") {
            let raw = line
                .replacingOccurrences(of: "#EXTINF:", with: "")
                .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                .first
            if let raw, let value = Double(raw.trimmingCharacters(in: .whitespaces)) {
                return value
            }
        }
        return nil
    }

    private func firstSampleFlags(in fragment: Data) throws -> UInt32 {
        let boxes = try BMFFSanityParser.parseTopLevel(fragment)
        func findTrun(in nodes: [BMFFBox]) -> BMFFBox? {
            for node in nodes {
                if node.type == "trun" { return node }
                if let nested = findTrun(in: node.children) { return nested }
            }
            return nil
        }

        let trun = try XCTUnwrap(findTrun(in: boxes))
        let flagsOffset = trun.startOffset + 28
        XCTAssertGreaterThanOrEqual(trun.startOffset + trun.size, flagsOffset + 4)
        return UInt32(fragment[flagsOffset]) << 24
            | UInt32(fragment[flagsOffset + 1]) << 16
            | UInt32(fragment[flagsOffset + 2]) << 8
            | UInt32(fragment[flagsOffset + 3])
    }

    private func flattenBMFFTypes(_ nodes: [BMFFInspectNode]) -> [String] {
        var types: [String] = []
        func walk(_ items: [BMFFInspectNode]) {
            for node in items {
                types.append(node.type)
                walk(node.children)
            }
        }
        walk(nodes)
        return types
    }

    // MARK: - DV Test Helpers

    private func makeDVProfile8PlanWithAudio() -> (NativeBridgePlan, TrackInfo, TrackInfo) {
        let videoTrack = TrackInfo(
            id: 1,
            trackType: .video,
            codecID: "V_MPEGH/ISO/HEVC",
            codecName: "hevc",
            isDefault: true,
            width: 3840,
            height: 1608,
            bitDepth: 10,
            codecPrivate: validSyntheticTestHVCC,
            colourPrimaries: 9,
            transferCharacteristic: 16,
            matrixCoefficients: 9
        )
        let audioTrack = TrackInfo(
            id: 2,
            trackType: .audio,
            codecID: "A_EAC3",
            codecName: "eac3",
            isDefault: true,
            sampleRate: 48_000,
            channels: 8
        )
        let plan = NativeBridgePlan(
            itemID: "dv-item",
            sourceID: "dv-source",
            sourceURL: URL(string: "https://example.com/dv.mkv")!,
            videoTrack: videoTrack,
            audioTrack: audioTrack,
            videoAction: .directPassthrough,
            audioAction: .directPassthrough,
            subtitleTracks: [],
            videoRangeType: "DOVIWithHDR10",
            dvProfile: 8,
            dvLevel: 6,
            dvBlSignalCompatibilityId: 1,
            whyChosen: "integration-dv-p8"
        )
        return (plan, videoTrack, audioTrack)
    }

    private func makeDVAVSamples() -> [Sample] {
        [
            Sample(
                trackID: 1,
                pts: CMTime(value: 0, timescale: 1_000_000_000),
                duration: CMTime(value: 41_708_333, timescale: 1_000_000_000),
                isKeyframe: true,
                data: Data([
                    0x00, 0x00, 0x00, 0x02, 0x46, 0x01,
                    0x00, 0x00, 0x00, 0x03, 0x40, 0x01, 0x0C,
                    0x00, 0x00, 0x00, 0x03, 0x42, 0x01, 0x01,
                    0x00, 0x00, 0x00, 0x03, 0x44, 0x01, 0xC0,
                    0x00, 0x00, 0x00, 0x04, 0x28, 0x01, 0xAA, 0xBB,
                    0x00, 0x00, 0x00, 0x04, 0x7C, 0x01, 0x11, 0x22
                ])
            ),
            Sample(
                trackID: 2,
                pts: CMTime(value: 0, timescale: 1_000_000_000),
                duration: CMTime(value: 32_000_000, timescale: 1_000_000_000),
                isKeyframe: true,
                data: Data([0x11, 0x22, 0x33, 0x44])
            )
        ]
    }
}

private actor MockDemuxer: Demuxer {
    private let samples: [Sample]
    private var index: Int = 0
    private var readCount = 0

    init(samples: [Sample]) {
        self.samples = samples
    }

    func open() async throws -> StreamInfo {
        StreamInfo(
            durationNanoseconds: 120_000_000_000,
            tracks: [TrackInfo(
                id: 1,
                trackType: .video,
                codecID: "V_MPEGH/ISO/HEVC",
                codecName: "hevc",
                isDefault: true,
                codecPrivate: validSyntheticTestHVCC
            )],
            hasChapters: false,
            seekable: true
        )
    }

    func readPacket() async throws -> DemuxedPacket? {
        guard index < samples.count else { return nil }
        readCount += 1
        defer { index += 1 }
        return DemuxedPacket(sample: samples[index])
    }

    func readSample() async throws -> Sample? {
        guard index < samples.count else { return nil }
        readCount += 1
        defer { index += 1 }
        return samples[index]
    }

    func seek(to timeNanoseconds: Int64) async throws -> Int64 {
        if let idx = samples.firstIndex(where: { $0.ptsNanoseconds >= timeNanoseconds }) {
            index = idx
            return samples[idx].ptsNanoseconds
        }
        index = samples.count
        return timeNanoseconds
    }

    func sampleReadCount() -> Int { readCount }
}

private actor FreezeableDemuxer: Demuxer {
    enum FreezeableDemuxerError: Error {
        case frozen
    }

    private let samples: [Sample]
    private var index: Int = 0
    private var frozen = false

    init(samples: [Sample]) {
        self.samples = samples
    }

    func freezeReads() {
        frozen = true
    }

    func open() async throws -> StreamInfo {
        StreamInfo(
            durationNanoseconds: Int64(samples.count) * 41_708_333,
            tracks: [TrackInfo(
                id: 1,
                trackType: .video,
                codecID: "V_MPEGH/ISO/HEVC",
                codecName: "hevc",
                isDefault: true,
                codecPrivate: validSyntheticTestHVCC
            )],
            hasChapters: false,
            seekable: true
        )
    }

    func readPacket() async throws -> DemuxedPacket? {
        guard !frozen else { throw FreezeableDemuxerError.frozen }
        guard index < samples.count else { return nil }
        defer { index += 1 }
        return DemuxedPacket(sample: samples[index])
    }

    func readSample() async throws -> Sample? {
        guard !frozen else { throw FreezeableDemuxerError.frozen }
        guard index < samples.count else { return nil }
        defer { index += 1 }
        return samples[index]
    }

    func seek(to timeNanoseconds: Int64) async throws -> Int64 {
        if let idx = samples.firstIndex(where: { $0.ptsNanoseconds >= timeNanoseconds }) {
            index = idx
            return samples[idx].ptsNanoseconds
        }
        index = samples.count
        return timeNanoseconds
    }
}

private actor DelayedReadDemuxer: Demuxer {
    private let samples: [Sample]
    private var index = 0
    private var activeReads = 0
    private var peakReads = 0

    init(samples: [Sample]) {
        self.samples = samples
    }

    func open() async throws -> StreamInfo {
        StreamInfo(
            durationNanoseconds: Int64(samples.count) * 41_708_333,
            tracks: [TrackInfo(
                id: 1,
                trackType: .video,
                codecID: "V_MPEGH/ISO/HEVC",
                codecName: "hevc",
                isDefault: true,
                codecPrivate: validSyntheticTestHVCC
            )],
            hasChapters: false,
            seekable: true
        )
    }

    func readPacket() async throws -> DemuxedPacket? {
        try await readSample().map(DemuxedPacket.init(sample:))
    }

    func readSample() async throws -> Sample? {
        activeReads += 1
        peakReads = max(peakReads, activeReads)
        defer { activeReads -= 1 }
        try await Task.sleep(nanoseconds: 5_000_000)
        guard index < samples.count else { return nil }
        defer { index += 1 }
        return samples[index]
    }

    func seek(to timeNanoseconds: Int64) async throws -> Int64 {
        index = samples.firstIndex(where: { $0.ptsNanoseconds >= timeNanoseconds }) ?? samples.count
        return index < samples.count ? samples[index].ptsNanoseconds : timeNanoseconds
    }

    func waitForActiveRead(attempts: Int = 100) async throws {
        for _ in 0..<attempts {
            if activeReads > 0 { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for a suspended demux read.")
    }

    func maximumConcurrentReads() -> Int { peakReads }
}

private actor GenerationCommitBarrier {
    private var entered = false
    private var released = false
    private var enteredContinuations: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

    func pause() async {
        entered = true
        enteredContinuations.forEach { $0.resume() }
        enteredContinuations.removeAll()
        guard !released else { return }
        await withCheckedContinuation { continuation in
            releaseContinuations.append(continuation)
        }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { continuation in
            enteredContinuations.append(continuation)
        }
    }

    func release() {
        released = true
        releaseContinuations.forEach { $0.resume() }
        releaseContinuations.removeAll()
    }
}

private actor PublicationOrderingProbe {
    enum Event: Equatable {
        case readerLookupEntered
        case readerLookupReleased
        case publicationCommitEntered
    }

    private var recordedEvents: [Event] = []

    func record(_ event: Event) {
        recordedEvents.append(event)
    }

    func events() -> [Event] {
        recordedEvents
    }
}

private actor PlaylistOperationTransitionProbe {
    private var recordedEvents: [PlaylistOperationTransition] = []
    private var countWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func record(_ event: PlaylistOperationTransition) {
        recordedEvents.append(event)
        let ready = countWaiters.filter { recordedEvents.count >= $0.0 }
        countWaiters.removeAll { recordedEvents.count >= $0.0 }
        ready.forEach { $0.1.resume() }
    }

    func waitUntilCount(_ count: Int) async {
        guard recordedEvents.count < count else { return }
        await withCheckedContinuation { continuation in
            countWaiters.append((count, continuation))
        }
    }

    func events() -> [PlaylistOperationTransition] {
        recordedEvents
    }
}

private actor SeekRaceDemuxer: Demuxer {
    private let samples: [Sample]
    private var index = 0
    private var delayNextRead = false
    private var delayedReadActive = false
    private var seekRacedRead = false

    init(samples: [Sample]) {
        self.samples = samples
    }

    func open() async throws -> StreamInfo {
        StreamInfo(
            durationNanoseconds: Int64(samples.count) * 41_708_333,
            tracks: [TrackInfo(
                id: 1,
                trackType: .video,
                codecID: "V_MPEGH/ISO/HEVC",
                codecName: "hevc",
                isDefault: true,
                codecPrivate: validSyntheticTestHVCC
            )],
            hasChapters: false,
            seekable: true
        )
    }

    func readPacket() async throws -> DemuxedPacket? {
        try await readSample().map(DemuxedPacket.init(sample:))
    }

    func readSample() async throws -> Sample? {
        if delayNextRead {
            delayNextRead = false
            delayedReadActive = true
            defer { delayedReadActive = false }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        guard index < samples.count else { return nil }
        defer { index += 1 }
        return samples[index]
    }

    func seek(to timeNanoseconds: Int64) async throws -> Int64 {
        seekRacedRead = delayedReadActive
        index = samples.firstIndex(where: { $0.ptsNanoseconds >= timeNanoseconds }) ?? samples.count
        return index < samples.count ? samples[index].ptsNanoseconds : timeNanoseconds
    }

    func delaySubsequentRead() { delayNextRead = true }

    func waitForDelayedRead(attempts: Int = 100) async throws {
        for _ in 0..<attempts {
            if delayedReadActive { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for delayed prefetch read.")
    }

    func seekBeganDuringDelayedRead() -> Bool { seekRacedRead }
}

private actor SingleTrackDemuxer: Demuxer {
    private let track: TrackInfo
    private let samples: [Sample]
    private var index = 0

    init(track: TrackInfo, samples: [Sample]) {
        self.track = track
        self.samples = samples
    }

    func open() async throws -> StreamInfo {
        let durationNs = samples.reduce(Int64(0)) { $0 + max(0, $1.durationNanoseconds) }
        return StreamInfo(
            durationNanoseconds: max(durationNs, 1_000_000_000),
            tracks: [track],
            hasChapters: false,
            seekable: true
        )
    }

    func readPacket() async throws -> DemuxedPacket? {
        guard index < samples.count else { return nil }
        defer { index += 1 }
        return DemuxedPacket(sample: samples[index])
    }

    func readSample() async throws -> Sample? {
        guard index < samples.count else { return nil }
        defer { index += 1 }
        return samples[index]
    }

    func seek(to timeNanoseconds: Int64) async throws -> Int64 {
        if let idx = samples.firstIndex(where: { $0.ptsNanoseconds >= timeNanoseconds }) {
            index = idx
            return samples[idx].ptsNanoseconds
        }
        index = samples.count
        return timeNanoseconds
    }
}

private actor MultiTrackDemuxer: Demuxer {
    private let tracks: [TrackInfo]
    private let samples: [Sample]
    private var index = 0

    init(tracks: [TrackInfo], samples: [Sample]) {
        self.tracks = tracks
        self.samples = samples.sorted { lhs, rhs in
            if lhs.ptsNanoseconds == rhs.ptsNanoseconds {
                return lhs.trackID < rhs.trackID
            }
            return lhs.ptsNanoseconds < rhs.ptsNanoseconds
        }
    }

    func open() async throws -> StreamInfo {
        let durationNs = samples.reduce(Int64(0)) { $0 + max(0, $1.durationNanoseconds) }
        return StreamInfo(
            durationNanoseconds: max(durationNs, 1_000_000_000),
            tracks: tracks,
            hasChapters: false,
            seekable: true
        )
    }

    func readPacket() async throws -> DemuxedPacket? {
        guard index < samples.count else { return nil }
        defer { index += 1 }
        return DemuxedPacket(sample: samples[index])
    }

    func readSample() async throws -> Sample? {
        guard index < samples.count else { return nil }
        defer { index += 1 }
        return samples[index]
    }

    func seek(to timeNanoseconds: Int64) async throws -> Int64 {
        if let idx = samples.firstIndex(where: { $0.ptsNanoseconds >= timeNanoseconds }) {
            index = idx
            return samples[idx].ptsNanoseconds
        }
        index = samples.count
        return timeNanoseconds
    }
}

private actor MockRepackager: Repackager {
    private var counter = 0

    func generateInitSegment(streamInfo: StreamInfo) async throws -> Data {
        _ = streamInfo
        return Data("init".utf8)
    }

    func generateFragment(packets: [DemuxedPacket]) async throws -> Data {
        counter += 1
        return Data("frag-\(counter)-\(packets.count)".utf8)
    }
}

private actor RecordingRepackager: Repackager {
    private var generatedTrackIDs: [[Int]] = []
    private var generatedSamples: [[Sample]] = []
    private var initCount = 0

    func generateInitSegment(streamInfo: StreamInfo) async throws -> Data {
        _ = streamInfo
        initCount += 1
        return Data("init".utf8)
    }

    func generateFragment(packets: [DemuxedPacket]) async throws -> Data {
        generatedTrackIDs.append(packets.map(\.trackID))
        generatedSamples.append(packets.map(\.asSample))
        return Data("frag-\(generatedTrackIDs.count)-\(packets.count)".utf8)
    }

    func trackIDs(forGeneratedFragmentAt index: Int) -> [Int] {
        guard generatedTrackIDs.indices.contains(index) else { return [] }
        return generatedTrackIDs[index]
    }

    func firstVideoSampleIsSync(forGeneratedFragmentAt index: Int) -> Bool? {
        guard generatedSamples.indices.contains(index) else { return nil }
        return generatedSamples[index].first(where: { $0.trackID == 1 })?.isKeyframe
    }

    func generatedFragmentCount() -> Int { generatedSamples.count }

    func generatedInitCount() -> Int { initCount }

    func samples(forGeneratedFragmentAt index: Int) -> [Sample] {
        guard generatedSamples.indices.contains(index) else { return [] }
        return generatedSamples[index]
    }
}

private actor SizedRepackager: Repackager {
    private let fragmentSizes: [Int]
    private var fragmentCount = 0

    init(fragmentSizes: [Int]) {
        self.fragmentSizes = fragmentSizes
    }

    func generateInitSegment(streamInfo: StreamInfo) async throws -> Data {
        _ = streamInfo
        return Data("init".utf8)
    }

    func generateFragment(packets: [DemuxedPacket]) async throws -> Data {
        _ = packets
        let index = min(fragmentCount, max(0, fragmentSizes.count - 1))
        let size = fragmentSizes.isEmpty ? 1 : fragmentSizes[index]
        fragmentCount += 1
        return Data(repeating: UInt8(fragmentCount & 0xFF), count: size)
    }

    func waitForFragmentCount(_ minimum: Int, attempts: Int = 150) async throws -> Int {
        for _ in 0..<attempts {
            if fragmentCount >= minimum { return fragmentCount }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return fragmentCount
    }
}
