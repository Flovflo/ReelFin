import CoreMedia
import Foundation

public struct VideoRenderDiagnostics: Equatable, Sendable {
    public var renderer: String
    public var displayedFrames: Int
    public var droppedFrames: Int
    public var renderLatencyMs: Double
    public var pixelFormat: String?
    public var hdrMode: HDRFormat

    public init(renderer: String) {
        self.renderer = renderer
        self.displayedFrames = 0
        self.droppedFrames = 0
        self.renderLatencyMs = 0
        self.hdrMode = .unknown
    }
}

public protocol VideoRenderer: Sendable {
    func render(frame: DecodedVideoFrame) async throws
    func flush() async
    func diagnostics() async -> VideoRenderDiagnostics
}

public struct VideoFrameScheduler: Sendable {
    public init() {}

    public func shouldDrop(
        frameTime: CMTime,
        clockTime: CMTime,
        tolerance: CMTime = CMTime(value: 80, timescale: 1000)
    ) -> Bool {
        frameTime < clockTime - tolerance
    }
}
