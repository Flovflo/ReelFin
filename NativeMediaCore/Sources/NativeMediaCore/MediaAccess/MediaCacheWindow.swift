import Foundation

public struct MediaCacheWindow: Sendable {
    public var maximumBytes: Int
    public private(set) var ranges: [ByteRange]

    public init(maximumBytes: Int = 32 * 1024 * 1024, ranges: [ByteRange] = []) {
        self.maximumBytes = maximumBytes
        self.ranges = ranges
    }

    public mutating func record(_ range: ByteRange) {
        ranges.append(range)
        coalesce()
        while ranges.reduce(0, { $0 + $1.length }) > maximumBytes, !ranges.isEmpty {
            ranges.removeFirst()
        }
    }

    public func contains(_ range: ByteRange) -> Bool {
        ranges.contains { cached in
            cached.offset <= range.offset
                && cached.offset + Int64(cached.length) >= range.offset + Int64(range.length)
        }
    }

    private mutating func coalesce() {
        let sorted = ranges.sorted { $0.offset < $1.offset }
        ranges = sorted.reduce(into: []) { partial, next in
            guard let last = partial.last else {
                partial.append(next)
                return
            }
            let lastEnd = last.offset + Int64(last.length)
            guard next.offset <= lastEnd else {
                partial.append(next)
                return
            }
            partial[partial.count - 1].length = Int(max(lastEnd, next.offset + Int64(next.length)) - last.offset)
        }
    }
}
