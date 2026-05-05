import CryptoKit
import Foundation
import NativeMediaCore

public actor MediaGatewayStore {
    public struct Configuration: Sendable {
        public var chunkSize: Int
        public var maxBytes: Int
        public var ttlSeconds: TimeInterval?

        public init(
            chunkSize: Int = 1 * 1_024 * 1_024,
            maxBytes: Int = 8 * 1_024 * 1_024 * 1_024,
            ttlSeconds: TimeInterval? = 14 * 24 * 60 * 60
        ) {
            self.chunkSize = max(1, chunkSize)
            self.maxBytes = max(0, maxBytes)
            self.ttlSeconds = ttlSeconds
        }
    }

    let rootURL: URL
    let fileManager: FileManager
    private let configuration: Configuration
    private let index: MediaGatewayIndex

    public init(
        directoryURL: URL? = nil,
        configuration: Configuration = Configuration(),
        fileManager: FileManager = .default
    ) throws {
        self.fileManager = fileManager
        self.configuration = configuration
        self.rootURL = directoryURL ?? Self.defaultRootDirectoryURL(fileManager: fileManager)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        self.index = try MediaGatewayIndex(directoryURL: rootURL, fileManager: fileManager)
    }

    public func read(range: ByteRange, key: MediaGatewayCacheKey) async throws -> Data? {
        guard range.offset >= 0, range.length > 0 else { throw MediaAccessError.invalidRange(range) }
        let chunks = try coveredChunks(for: range, key: key)
        guard chunks.reduce(0, { $0 + $1.slice.count }) == range.length else { return nil }
        var result = Data()
        for chunk in chunks {
            let data = try Data(contentsOf: chunk.url)
            result.append(data[chunk.slice])
        }
        _ = try await index.touch(key: key)
        return result
    }

    public func write(range: ByteRange, data: Data, key: MediaGatewayCacheKey) async throws {
        guard range.offset >= 0, range.length == data.count, range.length > 0 else {
            throw MediaAccessError.invalidRange(range)
        }
        let finalURL = fileURL(for: range, key: key)
        let partialURL = partialURL(for: range, key: key)
        try fileManager.createDirectory(at: finalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: partialURL.path) {
            try fileManager.removeItem(at: partialURL)
        }
        try data.write(to: partialURL, options: .atomic)
        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
        }
        try fileManager.moveItem(at: partialURL, to: finalURL)
        try await index.upsert(key: key, byteSize: byteSize(for: key), ttl: configuration.ttlSeconds)
        try await trim(budget: configuration.maxBytes, protectedKeys: [key])
    }

    public func coveredRanges(key: MediaGatewayCacheKey) async throws -> [ByteRange] {
        let entries = try rangeEntries(for: key)
        return coalesced(entries.map(\.range))
    }

    public func trim(budget: Int, protectedKeys: Set<MediaGatewayCacheKey> = []) async throws {
        var total = await index.byteSize
        for record in await index.records() where total > budget {
            guard !protectedKeys.contains(record.key) else { continue }
            try removeKey(record.key)
            try await index.remove(key: record.key)
            total -= record.byteSize
        }
    }

    public func removeServerScope(serverID: String?, userID: String?) async throws {
        let records = await index.records()
        for record in records where matches(record.key, serverID: serverID, userID: userID) {
            try removeKey(record.key)
            try await index.remove(key: record.key)
        }
    }

    public func availableCapacityBytes() -> Int64 {
        #if os(tvOS)
        let values = try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return Int64(values?.volumeAvailableCapacity ?? configuration.maxBytes)
        #else
        let values = try? rootURL.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ])
        if let important = values?.volumeAvailableCapacityForImportantUsage {
            return important
        }
        return Int64(values?.volumeAvailableCapacity ?? configuration.maxBytes)
        #endif
    }

    public func partialFileURLForTesting(range: ByteRange, key: MediaGatewayCacheKey) throws -> URL {
        partialURL(for: range, key: key)
    }

    public static func clearDefaultCache() async throws {
        let url = defaultRootDirectoryURL(fileManager: .default)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
