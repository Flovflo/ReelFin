import Foundation

public struct NativePlaybackPlannerOptions: Sendable, Equatable {
    public var allowServerTranscodeFallback: Bool
    public var preferAppleHardwareDecode: Bool
    public var allowCustomDemuxers: Bool
    public var allowSoftwareDecode: Bool
    public var enableMetalRenderer: Bool
    public var enableExperimentalMKV: Bool
    public var enableExperimentalASS: Bool
    public var enableExperimentalPGS: Bool
    public var enableExperimentalTrueHD: Bool
    public var enableExperimentalDTS: Bool

    public init(
        allowServerTranscodeFallback: Bool = false,
        preferAppleHardwareDecode: Bool = true,
        allowCustomDemuxers: Bool = true,
        allowSoftwareDecode: Bool = true,
        enableMetalRenderer: Bool = true,
        enableExperimentalMKV: Bool = true,
        enableExperimentalASS: Bool = true,
        enableExperimentalPGS: Bool = true,
        enableExperimentalTrueHD: Bool = true,
        enableExperimentalDTS: Bool = true
    ) {
        self.allowServerTranscodeFallback = allowServerTranscodeFallback
        self.preferAppleHardwareDecode = preferAppleHardwareDecode
        self.allowCustomDemuxers = allowCustomDemuxers
        self.allowSoftwareDecode = allowSoftwareDecode
        self.enableMetalRenderer = enableMetalRenderer
        self.enableExperimentalMKV = enableExperimentalMKV
        self.enableExperimentalASS = enableExperimentalASS
        self.enableExperimentalPGS = enableExperimentalPGS
        self.enableExperimentalTrueHD = enableExperimentalTrueHD
        self.enableExperimentalDTS = enableExperimentalDTS
    }
}

public struct DemuxBackendPlan: Equatable, Sendable {
    public var backend: String
    public var packetExtractionReady: Bool
}

public struct DecodeBackendPlan: Equatable, Sendable {
    public var trackID: Int
    public var codec: String
    public var backend: String
    public var hardwareAccelerated: Bool
    public var failure: FallbackReason?
}

public struct SubtitleBackendPlan: Equatable, Sendable {
    public var trackID: Int?
    public var format: SubtitleFormat?
    public var backend: String
    public var failure: FallbackReason?
}

public struct NativePlaybackPlan: Equatable, Sendable {
    public var demux: DemuxBackendPlan
    public var video: DecodeBackendPlan?
    public var audio: DecodeBackendPlan?
    public var subtitle: SubtitleBackendPlan?
    public var canStartLocalPlayback: Bool
    public var fallbackReasons: [FallbackReason]
    public var diagnostics: NativePlayerDiagnostics
}

public struct NativePlaybackPlanner: Sendable {
    private let options: NativePlaybackPlannerOptions

    public init(options: NativePlaybackPlannerOptions = NativePlaybackPlannerOptions()) {
        self.options = options
    }

    public func makePlan(probe: ProbeResult, stream: DemuxerStreamInfo, access: MediaAccessMetrics) -> NativePlaybackPlan {
        let demux = demuxPlan(format: probe.format)
        let videoTrack = stream.tracks.first { $0.kind == .video }
        let audioTrack = stream.tracks.first { $0.kind == .audio }
        let subtitleTrack = stream.tracks.first { $0.kind == .subtitle }
        let video = videoTrack.map(videoPlan)
        let audio = audioTrack.map(audioPlan)
        let subtitle = subtitleTrack.map(subtitlePlan)
        let videoRendererFailure = videoRendererFailure(format: probe.format, video: video)
        let audioRendererFailure = audioRendererFailure(format: probe.format, audioTrack: audioTrack)
        let demuxFailure: FallbackReason? = demux.packetExtractionReady
            ? nil
            : .matroskaPacketExtractionIncomplete(trackID: videoTrack?.trackId ?? -1)
        let fatalFailures = [video?.failure, videoRendererFailure, demuxFailure].compactMap { $0 }
        let degradedModuleFailures = [audio?.failure, subtitle?.failure, audioRendererFailure].compactMap { $0 }
        let failures = fatalFailures + degradedModuleFailures
        var diagnostics = diagnosticsBase(probe: probe, stream: stream, access: access, demux: demux)
        diagnostics.videoCodec = video?.codec
        diagnostics.videoDecoderBackend = video?.backend
        diagnostics.hardwareDecode = video?.hardwareAccelerated ?? false
        diagnostics.hdrFormat = videoTrack?.hdrMetadata?.format ?? .unknown
        diagnostics.dolbyVisionProfile = videoTrack?.hdrMetadata?.dolbyVision?.profile
        diagnostics.audioCodec = audio?.codec
        diagnostics.audioDecoderBackend = audio?.backend
        if probe.format == .mp4 || probe.format == .mov {
            diagnostics.rendererBackend = "AVSampleBufferDisplayLayer"
            diagnostics.audioRendererBackend = "AVSampleBufferAudioRenderer"
            diagnostics.masterClock = "AVSampleBufferRenderSynchronizer"
        } else if probe.format == .matroska || probe.format == .webm {
            diagnostics.rendererBackend = videoRendererFailure == nil ? "AVSampleBufferDisplayLayer(compressed)" : "missing"
            diagnostics.audioRendererBackend = audioRendererFailure == nil ? "AVSampleBufferAudioRenderer" : "missing"
            diagnostics.masterClock = "VideoPTSClock"
        } else if probe.format == .mpegTS || probe.format == .m2ts {
            diagnostics.rendererBackend = videoRendererFailure == nil ? "AVSampleBufferDisplayLayer(compressed-ts)" : "missing"
            diagnostics.audioRendererBackend = audioRendererFailure == nil ? "AVSampleBufferAudioRenderer" : "missing"
            diagnostics.masterClock = "MPEGTS90kClock"
        }
        diagnostics.subtitleFormat = subtitle?.format
        diagnostics.unsupportedModules = failures.map { $0.localizedDescription }
        diagnostics.failureReason = fatalFailures.first?.localizedDescription
        let canStart = fatalFailures.isEmpty && video != nil
        return NativePlaybackPlan(
            demux: demux,
            video: video,
            audio: audio,
            subtitle: subtitle,
            canStartLocalPlayback: canStart,
            fallbackReasons: failures,
            diagnostics: diagnostics
        )
    }

    private func demuxPlan(format: ContainerFormat) -> DemuxBackendPlan {
        switch format {
        case .mp4, .mov:
            return DemuxBackendPlan(backend: "MP4Demuxer(AVAssetReader)", packetExtractionReady: true)
        case .matroska, .webm:
            return DemuxBackendPlan(backend: "MatroskaDemuxer(EBML)", packetExtractionReady: true)
        case .mpegTS, .m2ts:
            return DemuxBackendPlan(backend: "MPEGTransportStreamDemuxer(PAT/PMT/PES)", packetExtractionReady: true)
        default:
            return DemuxBackendPlan(backend: "missing", packetExtractionReady: false)
        }
    }

    private func videoPlan(track: MediaTrack) -> DecodeBackendPlan {
        let codec = track.codec.lowercased()
        let hardware = ["h264", "hevc", "h265", "avc1", "hvc1", "hev1"].contains(codec)
        let needsSoftwareModule = ["av1", "vp9", "mpeg2", "vc1", "vfw"].contains(codec)
        let missing = needsSoftwareModule ? FallbackReason.decoderBackendMissing(codec: "\(codec) software decoder") : nil
        let backend = hardware ? "VideoToolbox" : (needsSoftwareModule ? "software-module-planned" : "missing")
        let failure = missing ?? (hardware ? nil : FallbackReason.decoderBackendMissing(codec: codec))
        return DecodeBackendPlan(
            trackID: track.trackId,
            codec: codec,
            backend: backend,
            hardwareAccelerated: hardware,
            failure: failure
        )
    }

    private func audioPlan(track: MediaTrack) -> DecodeBackendPlan {
        let codec = track.codec.lowercased()
        let apple = ["aac", "mp3", "alac", "ac3", "eac3", "flac", "opus", "pcm"].contains(codec)
        let softwarePlanned = (codec == "truehd" && options.enableExperimentalTrueHD) || (codec == "dts" && options.enableExperimentalDTS)
        let backend = apple ? "AppleAudioToolbox" : (softwarePlanned ? "software-module-planned" : "missing")
        let failure = apple ? nil : FallbackReason.decoderBackendMissing(codec: "\(codec) software decoder")
        return DecodeBackendPlan(trackID: track.trackId, codec: codec, backend: backend, hardwareAccelerated: false, failure: failure)
    }

    private func subtitlePlan(track: MediaTrack) -> SubtitleBackendPlan {
        let format = MatroskaCodecMapper.subtitleFormat(track.codecID ?? track.codec)
        let textAllowed = [.srt, .webVTT, .ass, .ssa, .matroskaText].contains(format)
        let imagePacketModelOnly = (format == .pgs && options.enableExperimentalPGS) || format == .vobSub
        let backend = textAllowed ? "SubtitleOverlayView" : (imagePacketModelOnly ? "image-subtitle-packet-model" : "missing")
        let failure: FallbackReason? = textAllowed
            ? nil
            : .decoderBackendMissing(codec: "\(track.codec) renderer")
        return SubtitleBackendPlan(
            trackID: track.trackId,
            format: format,
            backend: backend,
            failure: failure
        )
    }

    private func videoRendererFailure(format: ContainerFormat, video: DecodeBackendPlan?) -> FallbackReason? {
        guard let video else { return nil }
        switch format {
        case .mp4, .mov:
            return nil
        case .matroska, .webm:
            return video.failure == nil && video.hardwareAccelerated
                ? nil
                : .rendererUnavailable("No compressed sample-buffer renderer path exists for \(video.codec)")
        case .mpegTS, .m2ts:
            return video.failure == nil && video.hardwareAccelerated
                ? nil
                : .rendererUnavailable("No MPEG-TS compressed sample-buffer renderer path exists for \(video.codec)")
        default:
            return .rendererUnavailable("No renderer backend exists for \(format.rawValue)")
        }
    }

    private func audioRendererFailure(format: ContainerFormat, audioTrack: MediaTrack?) -> FallbackReason? {
        guard let audioTrack else { return nil }
        switch format {
        case .mp4, .mov:
            return nil
        case .matroska, .webm:
            let codec = audioTrack.codec.lowercased()
            return ["aac", "ac3", "eac3", "mp3", "alac", "flac", "opus", "pcm"].contains(codec)
                ? nil
                : .rendererUnavailable("Matroska audio packets for \(audioTrack.codec) need a software/audio renderer backend")
        case .mpegTS, .m2ts:
            let codec = audioTrack.codec.lowercased()
            return ["aac", "ac3", "eac3", "mp3"].contains(codec)
                ? nil
                : .rendererUnavailable("MPEG-TS audio packets for \(audioTrack.codec) need an audio renderer backend")
        default:
            return .rendererUnavailable("No audio renderer backend exists for \(format.rawValue)")
        }
    }

    private func diagnosticsBase(
        probe: ProbeResult,
        stream: DemuxerStreamInfo,
        access: MediaAccessMetrics,
        demux: DemuxBackendPlan
    ) -> NativePlayerDiagnostics {
        var diagnostics = NativePlayerDiagnostics(container: probe.format, demuxer: demux.backend)
        diagnostics.byteSourceType = "HTTPRangeByteSource"
        diagnostics.bufferedRanges = access.bufferedRanges
        diagnostics.networkMbps = access.readThroughputMbps
        return diagnostics
    }
}
