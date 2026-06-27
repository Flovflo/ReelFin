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

    /// Emitted every time a `write` extends a key's cached coverage. The cache resource loader's
    /// serve continuations wake off this — the store is the SINGLE coverage authority (no mirror
    /// map), so serving can never desync from what is actually on disk.
    public struct CoverageEvent: Sendable {
        public let storageID: String
        public let advancedToOffset: Int64
    }
    public nonisolated let coverageEvents: AsyncStream<CoverageEvent>
    private let coverageContinuation: AsyncStream<CoverageEvent>.Continuation

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
        (self.coverageEvents, self.coverageContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(256))
    }

    /// The on-disk storage identifier for a key. `CoverageEvent.storageID` carries this value, so
    /// a serve loop subscribed to `coverageEvents` matches events to its key with this. Pure
    /// function of the key (SHA-256 of its storage identity) — safe to call off the actor.
    public nonisolated func storageIdentifier(for key: MediaGatewayCacheKey) -> String {
        let hash = SHA256.hash(data: Data(key.storageIdentity.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
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
        // NOTE: deliberately NOT calling index.touch here — touch-on-read persisted the whole
        // index JSON on every served chunk (a write storm on the hot serve path). LRU recency is
        // good enough from write time for this cache's purpose.
        return result
    }

    /// Never-cut serve primitive: returns the longest CONTIGUOUS slice that exists starting at
    /// `offset` (1...maxLength bytes), or nil if `offset` itself isn't cached. Unlike `read`, this
    /// serves whatever is available right now so AVPlayer keeps getting bytes while the downloader
    /// is still filling ahead.
    public func readAvailablePrefix(from offset: Int64, maxLength: Int, key: MediaGatewayCacheKey) async throws -> Data? {
        guard offset >= 0, maxLength > 0 else { return nil }
        let entries = try rangeEntries(for: key) // sorted by offset
        var cursor = offset
        let targetEnd = offset + Int64(maxLength)
        var result = Data()
        for entry in entries {
            let entryEnd = entry.range.offset + Int64(entry.range.length)
            if entryEnd <= cursor { continue }          // already consumed / before offset
            if entry.range.offset > cursor { break }    // gap at the cursor → stop (contiguous only)
            let upper = min(targetEnd, entryEnd)
            let sliceStart = Int(cursor - entry.range.offset)
            let sliceEnd = Int(upper - entry.range.offset)
            let data = try Data(contentsOf: entry.url)
            result.append(data[(data.startIndex + sliceStart)..<(data.startIndex + sliceEnd)])
            cursor = upper
            if cursor >= targetEnd { break }
        }
        guard cursor > offset else { return nil }
        return result
    }

    /// The first offset NOT yet contiguously cached starting from `offset` (== `offset` if the
    /// byte at `offset` is missing). Lets the downloader know where to anchor.
    public func contiguousEnd(from offset: Int64, key: MediaGatewayCacheKey) async throws -> Int64 {
        guard offset >= 0 else { return offset }
        let entries = try rangeEntries(for: key)
        var cursor = offset
        for entry in entries {
            let entryEnd = entry.range.offset + Int64(entry.range.length)
            if entryEnd <= cursor { continue }
            if entry.range.offset > cursor { break }
            cursor = max(cursor, entryEnd)
        }
        return cursor
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
        // Wake any serve continuation waiting for coverage past this write.
        coverageContinuation.yield(CoverageEvent(storageID: storageID(for: key), advancedToOffset: range.offset + Int64(range.length)))
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
