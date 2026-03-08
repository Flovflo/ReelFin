import Foundation

/// Protocol defining the interface for a media demuxer used in the native bridge.
public protocol Demuxer: Sendable {
    /// Opens the media stream, parses initial headers (e.g., EBML + Tracks for MKV),
    /// and returns high-level stream information.
    ///
    /// - Throws: `NativeBridgeError.demuxerFailed` if parsing headers fails.
    func open() async throws -> StreamInfo

    /// Reads the next packet (frame/audio block) from the stream.
    ///
    /// - Returns: The next `DemuxedPacket`, or `nil` if EOF is reached.
    /// - Throws: `NativeBridgeError` if reading fails.
    func readPacket() async throws -> DemuxedPacket?

    /// Reads the next packet as a timing-rich sample model.
    /// Default implementation bridges from `readPacket()`.
    func readSample() async throws -> Sample?

    /// Seeks to the closest keyframe before or at the specified time.
    ///
    /// - Parameter timeNanoseconds: The target time in nanoseconds.
    /// - Returns: The actual time seeked to in nanoseconds.
    /// - Throws: `NativeBridgeError.seekFailed` if seeking fails or is unsupported.
    func seek(to timeNanoseconds: Int64) async throws -> Int64
}

public extension Demuxer {
    func readSample() async throws -> Sample? {
        try await readPacket()?.asSample
    }
}
