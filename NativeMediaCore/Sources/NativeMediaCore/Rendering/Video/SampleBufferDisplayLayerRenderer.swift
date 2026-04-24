import AVFoundation
import QuartzCore

public actor SampleBufferDisplayLayerRenderer: VideoRenderer {
    private let layer: AVSampleBufferDisplayLayer
    private var snapshot = VideoRenderDiagnostics(renderer: "AVSampleBufferDisplayLayer")

    public init(layer: AVSampleBufferDisplayLayer = AVSampleBufferDisplayLayer()) {
        self.layer = layer
    }

    public func render(frame: DecodedVideoFrame) async throws {
        guard let sampleBuffer = frame.sampleBuffer else {
            snapshot.droppedFrames += 1
            throw FallbackReason.rendererUnavailable("decoded frame has no CMSampleBuffer")
        }
        layer.enqueue(sampleBuffer)
        snapshot.displayedFrames += 1
        snapshot.hdrMode = frame.hdrMetadata?.format ?? .unknown
    }

    public func flush() async {
        layer.flush()
    }

    public func diagnostics() async -> VideoRenderDiagnostics {
        snapshot
    }
}
