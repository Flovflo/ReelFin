import CoreMedia
import Foundation

struct NativeMatroskaSampleBufferMetrics {
    var state = "idle"
    var videoPacketCount = 0
    var audioPacketCount = 0
    var audioRenderedSampleCount = 0
    var maxAudioSamplesPerBuffer = 0
    var videoPrimedPacketCount = 0
    var audioPrimedPacketCount = 0
    var droppedFrames = 0
    var currentPTS: Double = 0
    var audioPTS: Double = 0
    var playbackTime: Double = 0
    var startTime: Double = 0
    var videoQueueDepth = 0
    var audioQueueDepth = 0
    var videoQueuedSeconds: Double = 0
    var audioQueuedSeconds: Double = 0
    var videoAheadSeconds: Double = 0
    var audioAheadSeconds: Double = 0
    var audioUnderruns = 0
    var audioRebufferCount = 0
    var videoPrerollHidden = 0
    var audioPrerollDropped = 0
    var audioPTSRewrites = 0
    var maxAudioPTSCorrectionSeconds: Double = 0
    var audioStarvationTicks = 0
    var audioStarvationSeconds: Double = 0
    var videoDecoderBackend = "none"
    var audioDecoderBackend = "none"
    var activeSubtitleText: String?
    var unsupportedModules: [String] = []
    var failure: String?

    var requiresAudioForBuffering: Bool {
        audioDecoderBackend != "none" && audioDecoderBackend != "failed" && audioDecoderBackend != "degraded"
    }

    func overlayLines(base: [String]) -> [String] {
        var lines = base.filter { !$0.hasPrefix("state=") && !$0.hasPrefix("packets ") }
        lines.insert("state=\(state)", at: 0)
        lines.append("packets video=\(videoPacketCount) audio=\(audioPacketCount)")
        lines.append("audioSamples rendered=\(audioRenderedSampleCount) maxPerBuffer=\(maxAudioSamplesPerBuffer)")
        lines.append("videoDecoderBackend=\(videoDecoderBackend)")
        lines.append("audioDecoderBackend=\(audioDecoderBackend)")
        lines.append("rendererBackend=AVSampleBufferDisplayLayer(compressed)")
        lines.append("audioRendererBackend=AVSampleBufferAudioRenderer(compressed)")
        lines.append("masterClock=AVSampleBufferRenderSynchronizer")
        lines.append("startTime=\(String(format: "%.3f", startTime))")
        lines.append("currentPTS=\(String(format: "%.3f", currentPTS)) playbackTime=\(String(format: "%.3f", playbackTime))")
        lines.append("avDriftMs=\(String(format: "%.1f", (currentPTS - audioPTS) * 1000))")
        lines.append("bufferAhead video=\(String(format: "%.2f", videoAheadSeconds))s audio=\(String(format: "%.2f", audioAheadSeconds))s")
        lines.append("queue video=\(videoQueueDepth) audio=\(audioQueueDepth) audioQueued=\(String(format: "%.2f", audioQueuedSeconds))s videoQueued=\(String(format: "%.2f", videoQueuedSeconds))s")
        lines.append("primed video=\(videoPrimedPacketCount) audio=\(audioPrimedPacketCount)")
        lines.append("audioUnderruns=\(audioUnderruns) audioRebuffers=\(audioRebufferCount)")
        lines.append("audioPTSRewrites=\(audioPTSRewrites) maxAudioPTSCorrection=\(String(format: "%.3f", maxAudioPTSCorrectionSeconds))s starvationTicks=\(audioStarvationTicks) starvation=\(String(format: "%.2f", audioStarvationSeconds))s")
        lines.append("prerollHidden video=\(videoPrerollHidden) audioDropped=\(audioPrerollDropped)")
        lines.append("subtitleCueActive=\(activeSubtitleText == nil ? "false" : "true")")
        lines.append("droppedFrames=\(droppedFrames)")
        if !unsupportedModules.isEmpty {
            lines.append("unsupported=\(unsupportedModules.joined(separator: ","))")
        }
        if let failure {
            lines.append("failureModule=NativeMatroskaSampleBufferPlayer failure=\(failure)")
        }
        return lines
    }
}

enum NativeMatroskaSampleBufferPlayerError: LocalizedError {
    case noVideoTrack
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "Matroska demuxer found no video track for local sample-buffer playback."
        case .cancelled:
            return "Matroska sample-buffer playback was cancelled."
        }
    }
}

extension CMTime {
    var matroskaSafeSeconds: Double {
        guard isValid && !isIndefinite && !isNegativeInfinity && !isPositiveInfinity else {
            return 0
        }
        return seconds.isFinite ? seconds : 0
    }
}
