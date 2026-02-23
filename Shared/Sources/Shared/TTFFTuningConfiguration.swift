import Foundation

/// Configuration knobs for minimizing Time-To-First-Frame (TTFF).
///
/// Each property targets a specific bottleneck in the playback startup pipeline.
/// The defaults represent the optimal balance found through analysis of the
/// Jellyfin HLS pipeline and AVPlayer buffering behavior on iOS 26+.
public struct TTFFTuningConfiguration: Codable, Hashable, Sendable {

    // MARK: - HLS Segment Tuning

    /// HLS segment length in seconds. Shorter segments → less data before first
    /// frame but more overhead per segment. Jellyfin server default is 6.
    /// **Recommended: 3** for a good balance between startup and steady-state.
    public var hlsSegmentLengthSeconds: Int

    /// Minimum number of HLS segments the server must have ready before returning
    /// the master playlist. Lower values reduce initial transcode latency.
    /// **Recommended: 1** for fastest startup.
    public var hlsMinSegments: Int

    // MARK: - Subtitle Handling

    /// When `true`, subtitles are delivered externally (sidecar) rather than
    /// burned into the video stream. Burn-in forces a full transcode and
    /// increases TTFF significantly.
    public var disableSubtitleBurnIn: Bool

    // MARK: - AVPlayer Buffer Tuning

    /// `AVPlayerItem.preferredForwardBufferDuration` for Direct Play streams.
    /// Progressive files are local-quality so we need very little buffer.
    public var directPlayForwardBufferDuration: Double

    /// `AVPlayerItem.preferredForwardBufferDuration` for Remux (DirectStream) HLS.
    public var remuxForwardBufferDuration: Double

    /// `AVPlayerItem.preferredForwardBufferDuration` for Transcode HLS.
    public var transcodeForwardBufferDuration: Double

    /// Override `AVPlayer.automaticallyWaitsToMinimizeStalling` for Direct Play.
    /// Disabling this starts playback immediately, reducing TTFF at the risk of
    /// a brief stall on very slow connections.
    public var directPlayWaitsToMinimizeStalling: Bool

    /// Override for Remux streams.
    public var remuxWaitsToMinimizeStalling: Bool

    /// Override for Transcode streams.
    public var transcodeWaitsToMinimizeStalling: Bool

    // MARK: - Direct Play Optimization

    /// When `true` and the file is directly playable, use progressive download
    /// (`?static=true`) instead of the streaming URL. This avoids HLS manifest
    /// overhead entirely and is the fastest path to first frame.
    public var preferProgressiveDirectPlay: Bool

    // MARK: - Defaults

    public static let `default` = TTFFTuningConfiguration(
        hlsSegmentLengthSeconds: 3,
        hlsMinSegments: 1,
        disableSubtitleBurnIn: true,
        directPlayForwardBufferDuration: 2.0,
        remuxForwardBufferDuration: 4.0,
        transcodeForwardBufferDuration: 6.0,
        directPlayWaitsToMinimizeStalling: false,
        remuxWaitsToMinimizeStalling: false,
        transcodeWaitsToMinimizeStalling: true,
        preferProgressiveDirectPlay: true
    )

    public init(
        hlsSegmentLengthSeconds: Int = 3,
        hlsMinSegments: Int = 1,
        disableSubtitleBurnIn: Bool = true,
        directPlayForwardBufferDuration: Double = 2.0,
        remuxForwardBufferDuration: Double = 4.0,
        transcodeForwardBufferDuration: Double = 6.0,
        directPlayWaitsToMinimizeStalling: Bool = false,
        remuxWaitsToMinimizeStalling: Bool = false,
        transcodeWaitsToMinimizeStalling: Bool = true,
        preferProgressiveDirectPlay: Bool = true
    ) {
        self.hlsSegmentLengthSeconds = hlsSegmentLengthSeconds
        self.hlsMinSegments = hlsMinSegments
        self.disableSubtitleBurnIn = disableSubtitleBurnIn
        self.directPlayForwardBufferDuration = directPlayForwardBufferDuration
        self.remuxForwardBufferDuration = remuxForwardBufferDuration
        self.transcodeForwardBufferDuration = transcodeForwardBufferDuration
        self.directPlayWaitsToMinimizeStalling = directPlayWaitsToMinimizeStalling
        self.remuxWaitsToMinimizeStalling = remuxWaitsToMinimizeStalling
        self.transcodeWaitsToMinimizeStalling = transcodeWaitsToMinimizeStalling
        self.preferProgressiveDirectPlay = preferProgressiveDirectPlay
    }
}
