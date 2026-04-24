import Foundation

public struct NetworkBackpressureController: Sendable {
    public var maximumBufferedBytes: Int
    public var targetBufferedSeconds: Double

    public init(maximumBufferedBytes: Int = 48 * 1024 * 1024, targetBufferedSeconds: Double = 12) {
        self.maximumBufferedBytes = maximumBufferedBytes
        self.targetBufferedSeconds = targetBufferedSeconds
    }

    public func shouldPauseReads(bufferedBytes: Int, estimatedBitrate: Int?) -> Bool {
        if bufferedBytes >= maximumBufferedBytes { return true }
        guard let estimatedBitrate, estimatedBitrate > 0 else { return false }
        let seconds = Double(bufferedBytes * 8) / Double(estimatedBitrate)
        return seconds >= targetBufferedSeconds
    }
}
