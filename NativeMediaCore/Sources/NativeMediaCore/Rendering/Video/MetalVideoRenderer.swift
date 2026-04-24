import Foundation
import Metal

public actor MetalVideoRenderer: VideoRenderer {
    private let device: MTLDevice?
    private var snapshot = VideoRenderDiagnostics(renderer: "Metal")

    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        self.device = device
    }

    public func render(frame: DecodedVideoFrame) async throws {
        guard device != nil else {
            throw FallbackReason.rendererUnavailable("Metal device unavailable")
        }
        guard frame.pixelBuffer != nil else {
            snapshot.droppedFrames += 1
            throw FallbackReason.rendererUnavailable("Metal renderer requires CVPixelBuffer")
        }
        snapshot.displayedFrames += 1
        snapshot.hdrMode = frame.hdrMetadata?.format ?? .unknown
    }

    public func flush() async {}

    public func diagnostics() async -> VideoRenderDiagnostics {
        snapshot
    }
}
