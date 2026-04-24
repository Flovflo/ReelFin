@testable import ReelFinUI
import NativeMediaCore
import XCTest

@MainActor
final class NativePlayerConfigurationTests: XCTestCase {
    func testMatroskaProgressStartTimeUpdatesDoNotRestartPlayback() {
        let controller = NativeMatroskaSampleBufferPlayerController()
        _ = controller.view
        let url = URL(fileURLWithPath: "/tmp/native-\(UUID().uuidString).mkv")
        let headers = ["Authorization": "MediaBrowser Token=redacted"]

        controller.configure(
            url: url,
            headers: headers,
            container: .matroska,
            startTimeSeconds: 21.248,
            baseDiagnostics: [],
            isPaused: false,
            onDiagnostics: { _ in },
            onPlaybackTime: { _ in }
        )
        let generation = controller.playbackGeneration
        let pauseApplications = controller.pauseStateApplicationCount

        controller.configure(
            url: url,
            headers: headers,
            container: .matroska,
            startTimeSeconds: 42.0,
            baseDiagnostics: [],
            isPaused: false,
            onDiagnostics: { _ in },
            onPlaybackTime: { _ in }
        )

        XCTAssertEqual(controller.playbackGeneration, generation)
        XCTAssertEqual(controller.pauseStateApplicationCount, pauseApplications)
        controller.stopForDismantle()
    }

    func testMP4ProgressStartTimeUpdatesDoNotRestartPlayback() {
        let controller = NativeMP4SampleBufferPlayerController()
        _ = controller.view
        let url = URL(fileURLWithPath: "/tmp/native-\(UUID().uuidString).mp4")

        controller.configure(
            url: url,
            startTimeSeconds: 12.0,
            baseDiagnostics: [],
            isPaused: false,
            onDiagnostics: { _ in },
            onPlaybackTime: { _ in }
        )
        let generation = controller.playbackGeneration
        let pauseApplications = controller.pauseStateApplicationCount

        controller.configure(
            url: url,
            startTimeSeconds: 20.0,
            baseDiagnostics: [],
            isPaused: false,
            onDiagnostics: { _ in },
            onPlaybackTime: { _ in }
        )

        XCTAssertEqual(controller.playbackGeneration, generation)
        XCTAssertEqual(controller.pauseStateApplicationCount, pauseApplications)
        controller.stopForDismantle()
    }

    func testPauseStateGateAppliesOnlyWhenStateChanges() {
        var gate = NativePauseStateGate()

        XCTAssertTrue(gate.shouldApply(false))
        XCTAssertFalse(gate.shouldApply(false))
        XCTAssertTrue(gate.shouldApply(true))
        XCTAssertFalse(gate.shouldApply(true))

        gate.reset()
        XCTAssertTrue(gate.shouldApply(true))
    }

    func testMatroskaDiagnosticsDoNotKeepFailedAudioAsStartupRequirement() {
        var metrics = NativeMatroskaSampleBufferMetrics()

        metrics.audioDecoderBackend = "AppleAudioToolbox"
        XCTAssertTrue(metrics.requiresAudioForBuffering)

        metrics.audioDecoderBackend = "failed"
        XCTAssertFalse(metrics.requiresAudioForBuffering)

        metrics.audioDecoderBackend = "degraded"
        XCTAssertFalse(metrics.requiresAudioForBuffering)

        metrics.audioDecoderBackend = "none"
        XCTAssertFalse(metrics.requiresAudioForBuffering)
    }
}
