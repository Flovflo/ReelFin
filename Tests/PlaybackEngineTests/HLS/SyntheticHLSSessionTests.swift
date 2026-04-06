@testable import PlaybackEngine
import CoreMedia
import Foundation
import XCTest

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

    func testSeekInvalidationResetsCacheAndScheduler() async throws {
        let samples = makeSamples(count: 120)
        let demuxer = MockDemuxer(samples: samples)
        let repackager = MockRepackager()
        let session = SyntheticHLSSession(plan: makePlan(), demuxer: demuxer, repackager: repackager)

        try await session.prepare()
        let before = try await session.segment(sequence: 1)
        XCTAssertFalse(before.isEmpty)

        try await session.invalidateForSeek(targetPTS: 0)
        let after = try await session.segment(sequence: 0)
        XCTAssertFalse(after.isEmpty)
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

    func testStartupSegmentStaysShortWhenNextKeyframeIsFarAway() async throws {
        let samples = makeSamples(count: 360, keyframeInterval: 160)
        let demuxer = MockDemuxer(samples: samples)
        let repackager = MockRepackager()
        let session = SyntheticHLSSession(plan: makePlan(), demuxer: demuxer, repackager: repackager)

        try await session.prepare()
        let media = try await session.mediaPlaylist(preloadCount: 1)
        guard let firstDuration = firstEXTINFDuration(in: media) else {
            XCTFail("Missing first segment duration in media playlist.")
            return
        }

        XCTAssertLessThanOrEqual(
            firstDuration,
            2.05,
            "Startup segment should stay around two seconds to balance startup reliability and first-frame latency."
        )
    }

    func testStartupSegmentIncludesAudioWhenAudioTrackIsConfigured() async throws {
        let samples = makeInterleavedAVSamples()
        let demuxer = MockDemuxer(samples: samples)
        let repackager = RecordingRepackager()
        let session = SyntheticHLSSession(plan: makePlan(), demuxer: demuxer, repackager: repackager)

        try await session.prepare()
        _ = try await session.segment(sequence: 0)

        let firstFragmentTrackIDs = await repackager.trackIDs(forGeneratedFragmentAt: 0)
        XCTAssertTrue(firstFragmentTrackIDs.contains(1), "Startup fragment must include video samples.")
        XCTAssertTrue(firstFragmentTrackIDs.contains(2), "Startup fragment should include at least one audio sample when audio is selected.")
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

        let startupCount = try await waitForGeneratedSegmentCount(
            in: session,
            atLeast: 4
        )
        XCTAssertGreaterThanOrEqual(startupCount, 4)

        await session.promotePrefetch(preloadCount: 10, lookaheadSegments: 6)

        let promotedCount = try await waitForGeneratedSegmentCount(
            in: session,
            atLeast: 10
        )
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
        XCTAssertTrue(master.contains("CODECS=\"hvc1.2.4.L153.B0,ec-3\""), "Mode A must use hvc1 CODECS, got: \(master)")
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
            codecPrivate: Data([
                0x01, 0x22, 0x20, 0x00, 0x00, 0x00, 0x90, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x99, 0xF0, 0x00, 0xFC,
                0xFD, 0xFA, 0xFA, 0x00, 0x00, 0x0F, 0x03, 0xA0
            ]),
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
        XCTAssertTrue(master.contains("CODECS=\"hvc1.2.4.L153.B0\""), "Mode B must use hvc1 CODECS without audio, got: \(master)")
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
            codecPrivate: Data([
                0x01, 0x22, 0x20, 0x00, 0x00, 0x00, 0x90, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x99, 0xF0, 0x00, 0xFC,
                0xFD, 0xFA, 0xFA, 0x00, 0x00, 0x0F, 0x03, 0xA0
            ]),
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

    init(samples: [Sample]) {
        self.samples = samples
    }

    func open() async throws -> StreamInfo {
        StreamInfo(
            durationNanoseconds: 120_000_000_000,
            tracks: [TrackInfo(id: 1, trackType: .video, codecID: "V_MPEGH/ISO/HEVC", codecName: "hevc", isDefault: true)],
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
            tracks: [TrackInfo(id: 1, trackType: .video, codecID: "V_MPEGH/ISO/HEVC", codecName: "hevc", isDefault: true)],
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

    func generateInitSegment(streamInfo: StreamInfo) async throws -> Data {
        _ = streamInfo
        return Data("init".utf8)
    }

    func generateFragment(packets: [DemuxedPacket]) async throws -> Data {
        generatedTrackIDs.append(packets.map(\.trackID))
        return Data("frag-\(generatedTrackIDs.count)-\(packets.count)".utf8)
    }

    func trackIDs(forGeneratedFragmentAt index: Int) -> [Int] {
        guard generatedTrackIDs.indices.contains(index) else { return [] }
        return generatedTrackIDs[index]
    }
}
