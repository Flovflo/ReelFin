import Foundation

public actor MediaGatewayIndex {
    public struct Record: Codable, Sendable, Hashable {
        public let key: MediaGatewayCacheKey
        public let byteSize: Int
        public let createdAt: Date
        public let lastAccessAt: Date
        public let ttlSeconds: TimeInterval?
        public let accessCount: Int

        public var expirationDate: Date? {
            ttlSeconds.map { lastAccessAt.addingTimeInterval($0) }
        }

        public func isExpired(at date: Date) -> Bool {
            guard let expirationDate else { return false }
            return expirationDate <= date
        }

        fileprivate func touched(at date: Date) -> Record {
            Record(
                key: key,
                byteSize: byteSize,
                createdAt: createdAt,
                lastAccessAt: date,
                ttlSeconds: ttlSeconds,
                accessCount: accessCount + 1
            )
        }
    }

    private struct PersistedIndex: Codable {
        let schemaVersion: Int
        let records: [Record]
    }

    private struct LoadedState {
        let recordsByKey: [MediaGatewayCacheKey: Record]
        let totalByteSize: Int

        static let empty = LoadedState(recordsByKey: [:], totalByteSize: 0)
    }

    private static let schemaVersion = 1

    private let indexURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var recordsByKey: [MediaGatewayCacheKey: Record] = [:]
    private var totalByteSize: Int = 0

    public init(
        directoryURL: URL? = nil,
        indexFileName: String = "index.json",
        fileManager: FileManager = .default
    ) throws {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.encoder.dateEncodingStrategy = .secondsSince1970
        self.decoder.dateDecodingStrategy = .secondsSince1970

        let rootURL = directoryURL ?? Self.defaultRootDirectoryURL(fileManager: fileManager)
        if !fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }

        self.indexURL = rootURL.appendingPathComponent(indexFileName)
        let loaded = Self.loadState(indexURL: indexURL, encoder: encoder, decoder: decoder)
        self.recordsByKey = loaded.state.recordsByKey
        self.totalByteSize = loaded.state.totalByteSize
    }

    public var recordCount: Int {
        recordsByKey.count
    }

    public var byteSize: Int {
        totalByteSize
    }

    public func record(for key: MediaGatewayCacheKey, now: Date = Date()) -> Record? {
        guard let record = recordsByKey[key], !record.isExpired(at: now) else {
            return nil
        }
        return record
    }

    public func lruKeys(now: Date = Date()) -> [MediaGatewayCacheKey] {
        sortedRecords(now: now).map(\.key)
    }

    public func upsert(
        key: MediaGatewayCacheKey,
        byteSize: Int,
        ttl: TimeInterval? = nil,
        now: Date = Date()
    ) throws {
        _ = purgeExpired(now: now)

        let sanitizedSize = max(0, byteSize)
        if let existing = recordsByKey.removeValue(forKey: key) {
            totalByteSize -= existing.byteSize
        }

        let record = Record(
            key: key,
            byteSize: sanitizedSize,
            createdAt: now,
            lastAccessAt: now,
            ttlSeconds: ttl,
            accessCount: 0
        )
        recordsByKey[key] = record
        totalByteSize += sanitizedSize

        try persistLocked()
    }

    public func touch(key: MediaGatewayCacheKey, now: Date = Date()) throws -> Record? {
        _ = purgeExpired(now: now)

        guard let current = recordsByKey[key] else {
            return nil
        }

        let updated = current.touched(at: now)
        recordsByKey[key] = updated
        try persistLocked()
        return updated
    }

    public func remove(key: MediaGatewayCacheKey) throws {
        guard let removed = recordsByKey.removeValue(forKey: key) else {
            return
        }
        totalByteSize -= removed.byteSize
        try persistLocked()
    }

    public func pruneExpired(now: Date = Date()) throws -> [MediaGatewayCacheKey] {
        let removed = purgeExpired(now: now)
        if !removed.isEmpty {
            try persistLocked()
        }
        return removed
    }

    public func evictLRU(keepingMaxByteSize maxByteSize: Int, now: Date = Date()) throws -> [MediaGatewayCacheKey] {
        _ = purgeExpired(now: now)

        guard maxByteSize >= 0 else {
            let keys = sortedRecords(now: now).map(\.key)
            recordsByKey.removeAll()
            totalByteSize = 0
            try persistLocked()
            return keys
        }

        var evicted: [MediaGatewayCacheKey] = []
        var ordered = sortedRecords(now: now)

        while totalByteSize > maxByteSize, let candidate = ordered.first {
            ordered.removeFirst()
            if let removed = recordsByKey.removeValue(forKey: candidate.key) {
                totalByteSize -= removed.byteSize
                evicted.append(candidate.key)
            }
        }

        if !evicted.isEmpty {
            try persistLocked()
        }

        return evicted
    }

    public func persist() throws {
        try persistLocked()
    }

    public func reload() -> Bool {
        let loaded = Self.loadState(indexURL: indexURL, encoder: encoder, decoder: decoder)
        recordsByKey = loaded.state.recordsByKey
        totalByteSize = loaded.state.totalByteSize
        return loaded.loadedValidPayload
    }

    private func purgeExpired(now: Date) -> [MediaGatewayCacheKey] {
        let expired = recordsByKey.values
            .filter { $0.isExpired(at: now) }
            .sorted(by: Self.recordSort)

        guard !expired.isEmpty else { return [] }

        for record in expired {
            recordsByKey.removeValue(forKey: record.key)
            totalByteSize -= record.byteSize
        }

        return expired.map(\.key)
    }

    private func sortedRecords(now: Date) -> [Record] {
        recordsByKey.values
            .filter { !$0.isExpired(at: now) }
            .sorted(by: Self.recordSort)
    }

    private static func recordSort(_ lhs: Record, _ rhs: Record) -> Bool {
        if lhs.lastAccessAt != rhs.lastAccessAt {
            return lhs.lastAccessAt < rhs.lastAccessAt
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.key.storageIdentity < rhs.key.storageIdentity
    }

    private func persistLocked() throws {
        let payload = PersistedIndex(
            schemaVersion: Self.schemaVersion,
            records: recordsByKey.values.sorted(by: Self.recordSort)
        )
        let data = try encoder.encode(payload)
        try data.write(to: indexURL, options: .atomic)
    }

    private struct LoadOutcome {
        let state: LoadedState
        let loadedValidPayload: Bool
    }

    private static func loadState(
        indexURL: URL,
        encoder: JSONEncoder,
        decoder: JSONDecoder
    ) -> LoadOutcome {
        guard let data = try? Data(contentsOf: indexURL) else {
            return LoadOutcome(state: .empty, loadedValidPayload: false)
        }

        guard let payload = try? decoder.decode(PersistedIndex.self, from: data) else {
            try? writePersistedIndex(
                PersistedIndex(schemaVersion: schemaVersion, records: []),
                to: indexURL,
                encoder: encoder
            )
            return LoadOutcome(state: .empty, loadedValidPayload: false)
        }

        let state = makeState(from: payload.records)
        return LoadOutcome(state: state, loadedValidPayload: true)
    }

    private static func makeState(from records: [Record]) -> LoadedState {
        var nextRecords: [MediaGatewayCacheKey: Record] = [:]
        var nextSize = 0

        for record in records {
            nextRecords[record.key] = record
            nextSize += record.byteSize
        }

        return LoadedState(recordsByKey: nextRecords, totalByteSize: nextSize)
    }

    private static func writePersistedIndex(
        _ payload: PersistedIndex,
        to indexURL: URL,
        encoder: JSONEncoder
    ) throws {
        let data = try encoder.encode(payload)
        try data.write(to: indexURL, options: .atomic)
    }

    private static func defaultRootDirectoryURL(fileManager: FileManager) -> URL {
        let cacheRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return cacheRoot.appendingPathComponent("ReelFinMediaGateway", isDirectory: true)
    }
}
