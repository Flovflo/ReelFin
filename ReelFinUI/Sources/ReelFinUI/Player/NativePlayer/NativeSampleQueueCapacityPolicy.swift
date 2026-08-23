import Foundation

/// Chooses app-side sample queue depths for the Matroska sample-buffer surface.
///
/// The queues absorb network jitter between the demuxer (network-bound) and the
/// renderers (realtime-bound). A fixed depth tuned for mid-bitrate content drains
/// too fast on high-bitrate originals during throughput dips, which surfaces as
/// audible micro-dropouts before the starvation gate can react. Depth therefore
/// scales with the source bitrate and stays bounded so worst-case memory remains
/// acceptable for compressed sample buffers.
struct NativeSampleQueueCapacityPolicy: Equatable {
    var videoFrames: Int
    var audioPackets: Int

    static let baseline = NativeSampleQueueCapacityPolicy(videoFrames: 180, audioPackets: 320)
    static let maximum = NativeSampleQueueCapacityPolicy(videoFrames: 240, audioPackets: 480)

    static func capacity(
        sourceBitrateBps: Int?,
        isTVOS: Bool
    ) -> NativeSampleQueueCapacityPolicy {
        guard let sourceBitrateBps, sourceBitrateBps > 0 else { return .baseline }
        let highBitrateThresholdBps = isTVOS ? 16_000_000 : 20_000_000
        guard sourceBitrateBps >= highBitrateThresholdBps else { return .baseline }
        return .maximum
    }
}
