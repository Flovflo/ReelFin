import Foundation

/// Protocol defining the interface for repackaging demuxed packets into a container (e.g., fMP4).
public protocol Repackager: Sendable {
    /// Generates the initialization segment (e.g., ftyp + moov boxes in fMP4).
    /// This should be called once at the start of playback.
    ///
    /// - Parameter streamInfo: Metadata about the tracks to include in the moov box.
    /// - Returns: The binary data of the init segment.
    /// - Throws: `NativeBridgeError.repackagerFailed` if generation fails.
    func generateInitSegment(streamInfo: StreamInfo) async throws -> Data

    /// Generates a media fragment (e.g., moof + mdat boxes in fMP4) containing the provided packets.
    ///
    /// - Parameter packets: A list of demuxed packets to encapsulate.
    /// - Returns: The binary data of the media fragment.
    /// - Throws: `NativeBridgeError.repackagerFailed` if generation fails.
    func generateFragment(packets: [DemuxedPacket]) async throws -> Data

    /// Generates a media fragment from timing-rich samples.
    /// Default implementation bridges to `generateFragment(packets:)`.
    func generateFragment(samples: [Sample]) async throws -> Data

    /// Configures the repackager with a packaging decision before init segment generation.
    /// Default implementation is a no-op (for mocks and simple implementations).
    func setPackagingDecision(_ decision: NativeBridgePackagingDecision) async
}

public extension Repackager {
    func generateFragment(samples: [Sample]) async throws -> Data {
        try await generateFragment(packets: samples.map(DemuxedPacket.init(sample:)))
    }

    func setPackagingDecision(_ decision: NativeBridgePackagingDecision) async {
        // Default no-op for mocks and test conformers.
    }
}
