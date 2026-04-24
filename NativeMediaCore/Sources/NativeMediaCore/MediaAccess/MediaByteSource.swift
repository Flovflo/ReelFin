import Foundation

public struct ByteRange: Hashable, Sendable {
    public var offset: Int64
    public var length: Int

    public init(offset: Int64, length: Int) {
        self.offset = offset
        self.length = length
    }
}

public struct MediaAccessMetrics: Equatable, Sendable {
    public var currentOffset: Int64
    public var bufferedRanges: [ByteRange]
    public var readThroughputMbps: Double
    public var networkStalls: Int
    public var rangeRequestCount: Int
    public var seekCount: Int
    public var retryCount: Int

    public init(
        currentOffset: Int64 = 0,
        bufferedRanges: [ByteRange] = [],
        readThroughputMbps: Double = 0,
        networkStalls: Int = 0,
        rangeRequestCount: Int = 0,
        seekCount: Int = 0,
        retryCount: Int = 0
    ) {
        self.currentOffset = currentOffset
        self.bufferedRanges = bufferedRanges
        self.readThroughputMbps = readThroughputMbps
        self.networkStalls = networkStalls
        self.rangeRequestCount = rangeRequestCount
        self.seekCount = seekCount
        self.retryCount = retryCount
    }
}

public protocol MediaByteSource: Sendable {
    var url: URL { get }
    func read(range: ByteRange) async throws -> Data
    func size() async throws -> Int64?
    func cancel() async
    func metrics() async -> MediaAccessMetrics
}

public enum MediaAccessError: LocalizedError, Sendable, Equatable {
    case invalidRange(ByteRange)
    case nonHTTPResponse
    case httpStatus(Int)
    case cannotDetermineSize
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidRange(let range):
            return "Invalid byte range offset=\(range.offset) length=\(range.length)."
        case .nonHTTPResponse:
            return "Media byte source did not receive an HTTP response."
        case .httpStatus(let status):
            return "Media byte source HTTP request failed with status \(status)."
        case .cannotDetermineSize:
            return "Media byte source could not determine file size."
        case .cancelled:
            return "Media byte source request was cancelled."
        }
    }
}
