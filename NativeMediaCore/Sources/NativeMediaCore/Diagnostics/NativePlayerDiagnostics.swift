import Foundation

public struct NativePlayerDiagnostics: Equatable, Sendable {
    public var playbackState: String
    public var originalMediaRequested: Bool
    public var serverTranscodeUsed: Bool
    public var mediaSourceID: String?
    public var byteSourceType: String
    public var container: ContainerFormat
    public var demuxer: String
    public var videoPacketCount: Int
    public var audioPacketCount: Int
    public var videoCodec: String?
    public var videoDecoderBackend: String?
    public var hardwareDecode: Bool
    public var audioCodec: String?
    public var audioDecoderBackend: String?
    public var rendererBackend: String?
    public var audioRendererBackend: String?
    public var masterClock: String?
    public var currentPTS: Double
    public var currentPlaybackTime: Double
    public var subtitleCueActive: Bool
    public var subtitleFormat: SubtitleFormat?
    public var selectedAudioTrack: String?
    public var selectedSubtitleTrack: String?
    public var hdrFormat: HDRFormat
    public var dolbyVisionProfile: Int?
    public var bufferedRanges: [ByteRange]
    public var networkMbps: Double
    public var droppedFrames: Int
    public var decodeLatencyMs: Double
    public var renderLatencyMs: Double
    public var avSyncOffsetMs: Double
    public var unsupportedModules: [String]
    public var failureReason: String?

    public init(
        playbackState: String = "idle",
        originalMediaRequested: Bool = true,
        serverTranscodeUsed: Bool = false,
        mediaSourceID: String? = nil,
        byteSourceType: String = "none",
        container: ContainerFormat = .unknown,
        demuxer: String = "none"
    ) {
        self.playbackState = playbackState
        self.originalMediaRequested = originalMediaRequested
        self.serverTranscodeUsed = serverTranscodeUsed
        self.mediaSourceID = mediaSourceID
        self.byteSourceType = byteSourceType
        self.container = container
        self.demuxer = demuxer
        self.videoPacketCount = 0
        self.audioPacketCount = 0
        self.hardwareDecode = false
        self.currentPTS = 0
        self.currentPlaybackTime = 0
        self.subtitleCueActive = false
        self.hdrFormat = .unknown
        self.bufferedRanges = []
        self.networkMbps = 0
        self.droppedFrames = 0
        self.decodeLatencyMs = 0
        self.renderLatencyMs = 0
        self.avSyncOffsetMs = 0
        self.unsupportedModules = []
    }

    public var overlayLines: [String] {
        [
            "state=\(playbackState)",
            "originalMediaRequested=\(originalMediaRequested)",
            "serverTranscodeUsed=\(serverTranscodeUsed)",
            "byteSource=\(byteSourceType)",
            "container=\(container.rawValue)",
            "demuxer=\(demuxer)",
            "packets video=\(videoPacketCount) audio=\(audioPacketCount)",
            "video=\(videoCodec ?? "none") decoder=\(videoDecoderBackend ?? "none") hw=\(hardwareDecode)",
            "audio=\(audioCodec ?? "none") decoder=\(audioDecoderBackend ?? "none")",
            "renderer=\(rendererBackend ?? "none") audioRenderer=\(audioRendererBackend ?? "none")",
            "clock=\(masterClock ?? "none") pts=\(String(format: "%.3f", currentPTS)) time=\(String(format: "%.3f", currentPlaybackTime))",
            "subtitle=\(subtitleFormat?.rawValue ?? "none")",
            "subtitleCueActive=\(subtitleCueActive)",
            "selectedAudio=\(selectedAudioTrack ?? "none") selectedSubtitle=\(selectedSubtitleTrack ?? "none")",
            "hdr=\(hdrFormat.rawValue) dvProfile=\(dolbyVisionProfile.map(String.init) ?? "none")",
            "networkMbps=\(String(format: "%.2f", networkMbps)) dropped=\(droppedFrames)",
            "latency decode=\(String(format: "%.1f", decodeLatencyMs))ms render=\(String(format: "%.1f", renderLatencyMs))ms avSync=\(String(format: "%.1f", avSyncOffsetMs))ms",
            "unsupported=\(unsupportedModules.isEmpty ? "none" : unsupportedModules.joined(separator: ","))",
            "failure=\(failureReason ?? "none")"
        ]
    }
}
