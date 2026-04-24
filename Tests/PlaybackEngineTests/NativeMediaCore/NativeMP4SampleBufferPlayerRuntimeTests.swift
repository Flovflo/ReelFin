@testable import ReelFinUI
import XCTest

@MainActor
final class NativeMP4SampleBufferPlayerRuntimeTests: XCTestCase {
    func testNativeSampleBufferPlayerPumpsVideoAndAudioSamples() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        try await MP4PlaybackFixture.makeTinyH264AACMP4(at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        try await assertNativePlayerPumpsSamples(from: url)
    }

    func testNativeSampleBufferPlayerPumpsExtensionlessOriginalStream() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try await MP4PlaybackFixture.makeTinyH264AACMP4(at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        try await assertNativePlayerPumpsSamples(from: url)
    }

    private func assertNativePlayerPumpsSamples(from url: URL) async throws {
        let controller = NativeMP4SampleBufferPlayerController()
        _ = controller.view
        let sampleExpectation = expectation(description: "native sample-buffer player pumps video and audio")
        var didFulfill = false
        var lastDiagnostics: [String] = []

        controller.configure(
            url: url,
            startTimeSeconds: 0,
            baseDiagnostics: [],
            isPaused: false,
            onDiagnostics: { lines in
                lastDiagnostics = lines
                guard !didFulfill, let packetCounts = Self.packetCounts(from: lines) else { return }
                if packetCounts.video > 0 && packetCounts.audio > 0 {
                    didFulfill = true
                    sampleExpectation.fulfill()
                }
            },
            onPlaybackTime: { _ in }
        )

        await fulfillment(of: [sampleExpectation], timeout: 8)

        let packetCounts = try XCTUnwrap(Self.packetCounts(from: lastDiagnostics))
        XCTAssertGreaterThan(packetCounts.video, 0)
        XCTAssertGreaterThan(packetCounts.audio, 0)
        XCTAssertTrue(lastDiagnostics.contains("rendererBackend=AVSampleBufferDisplayLayer"))
        XCTAssertTrue(lastDiagnostics.contains("audioRendererBackend=AVSampleBufferAudioRenderer"))
        XCTAssertTrue(lastDiagnostics.contains("masterClock=AVSampleBufferRenderSynchronizer"))
    }

    private static func packetCounts(from lines: [String]) -> (video: Int, audio: Int)? {
        guard let line = lines.first(where: { $0.hasPrefix("packets video=") }) else { return nil }
        let parts = line.split(separator: " ")
        guard
            parts.count == 3,
            let video = Int(String(parts[1]).replacingOccurrences(of: "video=", with: "")),
            let audio = Int(String(parts[2]).replacingOccurrences(of: "audio=", with: ""))
        else {
            return nil
        }
        return (video, audio)
    }
}
