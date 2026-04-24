import Foundation

public actor ReadAheadController {
    private let source: any MediaByteSource
    private var task: Task<Void, Never>?

    public init(source: any MediaByteSource) {
        self.source = source
    }

    public func schedule(from offset: Int64, chunkSize: Int, chunkCount: Int) {
        task?.cancel()
        guard chunkSize > 0, chunkCount > 0 else { return }
        task = Task {
            for index in 0..<chunkCount where !Task.isCancelled {
                let range = ByteRange(offset: offset + Int64(index * chunkSize), length: chunkSize)
                _ = try? await source.read(range: range)
            }
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }
}
