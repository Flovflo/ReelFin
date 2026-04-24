import Foundation

public actor BufferedByteReader {
    private let source: any MediaByteSource
    private var offset: Int64

    public init(source: any MediaByteSource, offset: Int64 = 0) {
        self.source = source
        self.offset = offset
    }

    public func read(length: Int) async throws -> Data {
        let data = try await source.read(range: ByteRange(offset: offset, length: length))
        offset += Int64(data.count)
        return data
    }

    public func seek(to newOffset: Int64) {
        offset = max(0, newOffset)
    }

    public func position() -> Int64 {
        offset
    }
}
