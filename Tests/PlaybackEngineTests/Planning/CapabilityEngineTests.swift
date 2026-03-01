@testable import PlaybackEngine
import Shared
import XCTest

final class CapabilityEngineTests: XCTestCase {
    private let probe = JellyfinMediaProbe()

    func testDirectPlayPlanForCompatibleMP4() {
        let source = MediaSource(
            id: "s1",
            itemID: "i1",
            name: "mp4",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "eac3",
            supportsDirectPlay: true,
            supportsDirectStream: true,
            directStreamURL: URL(string: "https://example.com/video.mp4"),
            directPlayURL: URL(string: "https://example.com/video.mp4"),
            transcodeURL: URL(string: "https://example.com/master.m3u8")
        )

        let result = probe.probe(itemID: "i1", source: source)
        let input = PlaybackPlanningInput(
            itemID: "i1",
            probes: [result],
            device: DeviceCapabilityFingerprint.current(),
            allowTranscoding: true
        )
        let plan = CapabilityEngine().computePlan(input: input)

        XCTAssertEqual(plan.lane, .nativeDirectPlay)
        XCTAssertEqual(plan.sourceID, "s1")
    }

    func testJITPlanForMKVHEVC() {
        let source = MediaSource(
            id: "s2",
            itemID: "i2",
            name: "mkv-hevc",
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "eac3",
            supportsDirectPlay: false,
            supportsDirectStream: true,
            directStreamURL: URL(string: "https://example.com/video.mkv"),
            directPlayURL: nil,
            transcodeURL: URL(string: "https://example.com/master.m3u8")
        )

        let plan = CapabilityEngine().computePlan(
            input: PlaybackPlanningInput(
                itemID: "i2",
                probes: [probe.probe(itemID: "i2", source: source)],
                device: DeviceCapabilityFingerprint.current(),
                allowTranscoding: true
            )
        )

        XCTAssertEqual(plan.lane, .jitRepackageHLS)
        XCTAssertEqual(plan.selectedVideoCodec, "hevc")
    }

    func testTrueHDFallsBackToSurgicalTranscode() {
        let source = MediaSource(
            id: "s3",
            itemID: "i3",
            name: "mkv-truehd",
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "truehd",
            supportsDirectPlay: false,
            supportsDirectStream: true,
            directStreamURL: URL(string: "https://example.com/video.mkv"),
            directPlayURL: nil,
            transcodeURL: URL(string: "https://example.com/master.m3u8")
        )

        let plan = CapabilityEngine().computePlan(
            input: PlaybackPlanningInput(
                itemID: "i3",
                probes: [probe.probe(itemID: "i3", source: source)],
                device: DeviceCapabilityFingerprint.current(),
                allowTranscoding: true
            )
        )

        XCTAssertEqual(plan.lane, .surgicalFallback)
        XCTAssertEqual(plan.selectedAudioCodec, "aac")
    }

    func testRejectWhenNoPathAndNoTranscoding() {
        let source = MediaSource(
            id: "s4",
            itemID: "i4",
            name: "unknown",
            container: "avi",
            videoCodec: "mpeg2",
            audioCodec: "dts",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: nil
        )

        let plan = CapabilityEngine().computePlan(
            input: PlaybackPlanningInput(
                itemID: "i4",
                probes: [probe.probe(itemID: "i4", source: source)],
                device: DeviceCapabilityFingerprint.current(),
                allowTranscoding: false
            )
        )

        XCTAssertEqual(plan.lane, .rejected)
        XCTAssertEqual(plan.fallbackGraph, [.reject])
    }

    func testDirectPlayPlanForCommaSeparatedContainerList() {
        let source = MediaSource(
            id: "s5",
            itemID: "i5",
            name: "mp4-list",
            container: "mov,mp4,m4a,3gp,3g2,mj2",
            videoCodec: "hevc",
            audioCodec: "eac3",
            supportsDirectPlay: true,
            supportsDirectStream: true,
            directStreamURL: URL(string: "https://example.com/video.mp4"),
            directPlayURL: URL(string: "https://example.com/video.mp4"),
            transcodeURL: URL(string: "https://example.com/master.m3u8")
        )

        let plan = CapabilityEngine().computePlan(
            input: PlaybackPlanningInput(
                itemID: "i5",
                probes: [probe.probe(itemID: "i5", source: source)],
                device: DeviceCapabilityFingerprint.current(),
                allowTranscoding: true
            )
        )

        XCTAssertEqual(plan.lane, .nativeDirectPlay)
        XCTAssertEqual(plan.sourceID, "s5")
    }

    func testProbeKeepsPerTrackAudioCodecForPlanning() {
        let source = MediaSource(
            id: "s6",
            itemID: "i6",
            name: "mixed-audio",
            container: "mp4",
            videoCodec: "hevc",
            audioCodec: "eac3",
            supportsDirectPlay: true,
            supportsDirectStream: true,
            directStreamURL: URL(string: "https://example.com/video.mp4"),
            directPlayURL: URL(string: "https://example.com/video.mp4"),
            transcodeURL: URL(string: "https://example.com/master.m3u8"),
            audioTracks: [
                MediaTrack(id: "a1", title: "FR AAC", language: "fra", codec: "aac", isDefault: true, index: 1),
                MediaTrack(id: "a2", title: "FR E-AC-3", language: "fra", codec: "eac3", isDefault: false, index: 2)
            ]
        )

        let result = probe.probe(itemID: "i6", source: source)
        XCTAssertEqual(result.audioTracks.map(\.codec), ["aac", "eac3"])
    }
}
