import AVFoundation
import CoreMedia
import Foundation

public struct AudioRenderDiagnostics: Equatable, Sendable {
    public var renderer: String
    public var audioClockOffsetMs: Double
    public var renderedFrames: Int
    public var underruns: Int

    public init(renderer: String = "unknown", audioClockOffsetMs: Double = 0, renderedFrames: Int = 0, underruns: Int = 0) {
        self.renderer = renderer
        self.audioClockOffsetMs = audioClockOffsetMs
        self.renderedFrames = renderedFrames
        self.underruns = underruns
    }
}

public protocol AudioRenderer: Sendable {
    func render(frame: DecodedAudioFrame) async throws
    func pause() async
    func resume() async
    func diagnostics() async -> AudioRenderDiagnostics
}

public actor AVAudioEngineRenderer: AudioRenderer {
    private let engine = AVAudioEngine()
    private var snapshot = AudioRenderDiagnostics(renderer: "AVAudioEngine")

    public init() {}

    public func render(frame: DecodedAudioFrame) async throws {
        _ = frame
        snapshot.renderedFrames += 1
    }

    public func pause() async {
        engine.pause()
    }

    public func resume() async {
        if !engine.isRunning {
            try? engine.start()
        }
    }

    public func diagnostics() async -> AudioRenderDiagnostics {
        snapshot
    }
}
