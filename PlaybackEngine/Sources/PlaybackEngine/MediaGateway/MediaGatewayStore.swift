import CryptoKit
import Foundation
import NativeMediaCore

public actor MediaGatewayStore {
    public struct Configuration: Sendable {
        public var chunkSize: Int
        public var maxBytes: Int
        public var ttlSeconds: TimeInterval?
        /// Contiguous sub-block writes are APPENDED into segment files up to this size, instead of
        /// one file per ≥256KB sub-block. A 4K movie at one-file-per-sub-block reached tens of
        /// thousands of files, and the per-operation directory scan + per-write index rewrite
        /// eventually ran slower than realtime — the proven "deep cache but it still cuts
        /// mid-film" mechanism. ~32MB ≈ a few hundred files for a full 4K feature.
        public var segmentMaxBytes: Int
        /// Index persistence throttle: sync after this many bytes written…
        public var indexSyncBytes: Int
        /// …or this much time since the last sync, whichever comes first. `flushIndex()` forces it.
        public var indexSyncSeconds: TimeInterval

        public init(
            chunkSize: Int = 1 * 1_024 * 1_024,
            maxBytes: Int = 8 * 1_024 * 1_024 * 1_024,
            ttlSeconds: TimeInterval? = 14 * 24 * 60 * 60,
            segmentMaxBytes: Int = 32 * 1_024 * 1_024,
            indexSyncBytes: Int = 64 * 1_024 * 1_024,
            indexSyncSeconds: TimeInterval = 10
        ) {
            self.chunkSize = max(1, chunkSize)
            self.maxBytes = max(0, maxBytes)
            self.ttlSeconds = ttlSeconds
            self.segmentMaxBytes = max(1, segmentMaxBytes)
            self.indexSyncBytes = max(1, indexSyncBytes)
            self.indexSyncSeconds = max(0, indexSyncSeconds)
        }
    }

    let rootURL: URL
    let fileManager: FileManager
    private let configuration: Configuration
    private let index: MediaGatewayIndex

    /// In-memory coverage per key (storageID → sorted disk entries + total size). Loaded from disk
    /// ONCE per key, then maintained by every mutation — the disk is never re-scanned on the hot
    /// path. This is the single biggest scale fix for feature-length 4K playback.
    struct KeyState {
        var entries: [RangeEntry]   // sorted by offset, mirrors the .cache files exactly
        var byteSize: Int
    }
    private var keyStates: [String: KeyState] = [:]

    /// Index-sync throttle state: keys with unsynced writes + bytes written since the last sync.
    /// The clock starts at store creation so the FIRST write doesn't force an immediate sync.
    private var dirtyIndexKeys: [String: MediaGatewayCacheKey] = [:]
    private var unsyncedWriteBytes: Int = 0
    private var lastIndexSyncAt: Date = Date()

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

    deinit { coverageContinuation.finish() }

    /// The on-disk storage identifier for a key. `CoverageEvent.storageID` carries this value, so
    /// a serve loop subscribed to `coverageEvents` matches events to its key with this. Pure
    /// function of the key (SHA-256 of its storage identity) — safe to call off the actor.
    public nonisolated func storageIdentifier(for key: MediaGatewayCacheKey) -> String {
        let hash = SHA256.hash(data: Data(key.storageIdentity.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    public func read(range: ByteRange, key: MediaGatewayCacheKey) async throws -> Data? {
        guard range.offset >= 0, range.length > 0 else { throw MediaAccessError.invalidRange(range) }
        let chunks = coveredChunks(for: range, entries: try loadedEntries(for: key))
        guard chunks.reduce(0, { $0 + $1.lengthInFile }) == range.length else { return nil }
        var result = Data(capacity: range.length)
        for chunk in chunks {
            result.append(try readSlice(url: chunk.url, offsetInFile: chunk.offsetInFile, length: chunk.lengthInFile))
        }
        return result
    }

    /// Never-cut serve primitive: returns the longest CONTIGUOUS slice that exists starting at
    /// `offset` (1...maxLength bytes), or nil if `offset` itself isn't cached. Unlike `read`, this
    /// serves whatever is available right now so AVPlayer keeps getting bytes while the downloader
    /// is still filling ahead.
    public func readAvailablePrefix(from offset: Int64, maxLength: Int, key: MediaGatewayCacheKey) async throws -> Data? {
        guard offset >= 0, maxLength > 0 else { return nil }
        let entries = try loadedEntries(for: key)
        var cursor = offset
        let targetEnd = offset + Int64(maxLength)
        var result = Data()
        for entry in entries {
            let entryEnd = entry.range.offset + Int64(entry.range.length)
            if entryEnd <= cursor { continue }          // already consumed / before offset
            if entry.range.offset > cursor { break }    // gap at the cursor → stop (contiguous only)
            let upper = min(targetEnd, entryEnd)
            let sliceStart = cursor - entry.range.offset
            let sliceLength = Int(upper - cursor)
            result.append(try readSlice(url: entry.url, offsetInFile: sliceStart, length: sliceLength))
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
        let entries = try loadedEntries(for: key)
        var cursor = offset
        for entry in entries {
            let entryEnd = entry.range.offset + Int64(entry.range.length)
            if entryEnd <= cursor { continue }
            if entry.range.offset > cursor { break }
            cursor = max(cursor, entryEnd)
        }
        return cursor
    }

    /// Source total length persisted alongside the cached chunks, so a previously-played title can
    /// start straight from the disk cache WITHOUT probing the origin (the offline / never-cut
    /// promise). Stored as a plain sidecar (no `.cache` extension → ignored by the range scanner).
    public func persistedContentLength(key: MediaGatewayCacheKey) -> Int64? {
        let url = directoryURL(for: key).appendingPathComponent("content.length")
        guard let raw = try? String(contentsOf: url, encoding: .utf8),
              let value = Int64(raw.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else { return nil }
        return value
    }

    public func persistContentLength(_ length: Int64, key: MediaGatewayCacheKey) {
        guard length > 0 else { return }
        let directory = directoryURL(for: key)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? String(length).data(using: .utf8)?.write(to: directory.appendingPathComponent("content.length"), options: .atomic)
    }

    /// Persists `data` at `range`. Only the bytes NOT already covered are written (the serve-path
    /// on-demand fetch and the background downloader legitimately overlap); contiguous writes are
    /// appended into bounded segment files; index/trim maintenance is throttled off this hot path.
    public func write(range: ByteRange, data: Data, key: MediaGatewayCacheKey) async throws {
        guard range.offset >= 0, range.length == data.count, range.length > 0 else {
            throw MediaAccessError.invalidRange(range)
        }
        var state = try loadedState(for: key)
        let gaps = uncoveredSubranges(of: range, in: state.entries)
        guard !gaps.isEmpty else { return } // fully duplicate coverage → zero IO

        let directory = directoryURL(for: key)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var written = 0
        for gap in gaps {
            let sliceStart = data.startIndex + Int(gap.offset - range.offset)
            let slice = data[sliceStart..<(sliceStart + gap.length)]
            try persist(slice: Data(slice), at: gap, key: key, state: &state)
            written += gap.length
        }
        state.byteSize += written
        keyStates[storageID(for: key)] = state

        try await noteWrite(bytes: written, key: key)
        // Wake any serve continuation waiting for coverage past this write.
        coverageContinuation.yield(CoverageEvent(storageID: storageID(for: key), advancedToOffset: range.offset + Int64(range.length)))
    }

    /// Forces the throttled index/trim maintenance to run now. Call at end of playback (and from
    /// tests); during playback the throttle keeps it off the write hot path.
    public func flushIndex() async {
        try? await syncIndexNow()
    }

    /// Total bytes cached for one key (from the in-memory coverage — no disk scan).
    public func cachedByteSize(key: MediaGatewayCacheKey) async throws -> Int {
        try byteSize(for: key)
    }

    /// Range-aware eviction (blueprint §4): removes cached segments of `key` that end at or before
    /// `cutoff`, EXCEPT segments starting inside the protected head region (moov/init bytes needed
    /// by any rebuild/replay). Whole-segment granularity. Never touches bytes at/after `cutoff` —
    /// the forward reservoir is sacred. Returns the number of bytes freed.
    @discardableResult
    public func evictRanges(endingBefore cutoff: Int64, key: MediaGatewayCacheKey, protectingHeadBytes: Int64 = 0) async throws -> Int64 {
        guard cutoff > 0 else { return 0 }
        var state = try loadedState(for: key)
        var freed: Int64 = 0
        var kept: [RangeEntry] = []
        kept.reserveCapacity(state.entries.count)
        for entry in state.entries {
            let entryEnd = entry.range.offset + Int64(entry.range.length)
            let isBehindCutoff = entryEnd <= cutoff
            let isProtectedHead = entry.range.offset < protectingHeadBytes
            if isBehindCutoff && !isProtectedHead {
                try? fileManager.removeItem(at: entry.url)
                freed += Int64(entry.range.length)
            } else {
                kept.append(entry)
            }
        }
        guard freed > 0 else { return 0 }
        state.entries = kept
        state.byteSize -= Int(freed)
        keyStates[storageID(for: key)] = state
        dirtyIndexKeys[storageID(for: key)] = key // sync the shrink on the next throttled pass
        return freed
    }

    public func coveredRanges(key: MediaGatewayCacheKey) async throws -> [ByteRange] {
        let entries = try loadedEntries(for: key)
        return coalesced(entries.map(\.range))
    }

    public func trim(budget: Int, protectedKeys: Set<MediaGatewayCacheKey> = []) async throws {
        // Bring the index up to date with any throttled (unsynced) writes before judging the budget.
        try await flushIndexUpserts()
        var total = await index.byteSize
        for record in await index.records() where total > budget {
            guard !protectedKeys.contains(record.key) else { continue }
            try removeKey(record.key)
            try await index.remove(key: record.key)
            total -= record.byteSize
        }
    }

    public func removeServerScope(serverID: String?, userID: String?) async throws {
        try await flushIndexUpserts()
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

    // MARK: - In-memory coverage (loaded once, maintained by mutations)

    func loadedState(for key: MediaGatewayCacheKey) throws -> KeyState {
        let id = storageID(for: key)
        if let state = keyStates[id] { return state }
        let entries = try scanRangeEntriesFromDisk(for: key)
        let state = KeyState(entries: entries, byteSize: entries.reduce(0) { $0 + $1.range.length })
        keyStates[id] = state
        return state
    }

    func loadedEntries(for key: MediaGatewayCacheKey) throws -> [RangeEntry] {
        try loadedState(for: key).entries
    }

    /// Drops the cached coverage for a key (after its files were removed).
    func invalidateState(for key: MediaGatewayCacheKey) {
        keyStates[storageID(for: key)] = nil
        dirtyIndexKeys[storageID(for: key)] = nil
    }

    func byteSize(for key: MediaGatewayCacheKey) throws -> Int {
        try loadedState(for: key).byteSize
    }

    // MARK: - Write internals

    /// The sub-ranges of `range` not currently covered, in ascending order.
    private func uncoveredSubranges(of range: ByteRange, in entries: [RangeEntry]) -> [ByteRange] {
        var gaps: [ByteRange] = []
        var cursor = range.offset
        let end = range.offset + Int64(range.length)
        for entry in entries {
            let entryStart = entry.range.offset
            let entryEnd = entryStart + Int64(entry.range.length)
            if entryEnd <= cursor { continue }
            if entryStart >= end { break }
            if entryStart > cursor {
                gaps.append(ByteRange(offset: cursor, length: Int(min(entryStart, end) - cursor)))
            }
            cursor = max(cursor, entryEnd)
            if cursor >= end { break }
        }
        if cursor < end {
            gaps.append(ByteRange(offset: cursor, length: Int(end - cursor)))
        }
        return gaps
    }

    /// Persists one uncovered sub-range: appended to the adjacent segment file when possible
    /// (rename carries the new length — the filename is the coverage authority, so a crash between
    /// append and rename only leaves ignorable extra bytes), else written as a new segment file.
    private func persist(slice: Data, at gap: ByteRange, key: MediaGatewayCacheKey, state: inout KeyState) throws {
        if let idx = state.entries.firstIndex(where: {
            $0.range.offset + Int64($0.range.length) == gap.offset && $0.range.length < configuration.segmentMaxBytes
        }) {
            let entry = state.entries[idx]
            let grown = ByteRange(offset: entry.range.offset, length: entry.range.length + gap.length)
            let grownURL = fileURL(for: grown, key: key)
            let handle = try FileHandle(forWritingTo: entry.url)
            defer { try? handle.close() }
            // Seek to the LOGICAL end (named length), not the physical EOF — a crashed rename can
            // leave stray bytes past the named length, which must be overwritten, not extended.
            try handle.seek(toOffset: UInt64(entry.range.length))
            try handle.write(contentsOf: slice)
            try handle.close()
            if fileManager.fileExists(atPath: grownURL.path) {
                try fileManager.removeItem(at: grownURL)
            }
            try fileManager.moveItem(at: entry.url, to: grownURL)
            state.entries[idx] = RangeEntry(range: grown, url: grownURL)
        } else {
            let sub = ByteRange(offset: gap.offset, length: gap.length)
            let finalURL = fileURL(for: sub, key: key)
            let partialURL = partialURL(for: sub, key: key)
            if fileManager.fileExists(atPath: partialURL.path) {
                try fileManager.removeItem(at: partialURL)
            }
            try slice.write(to: partialURL, options: .atomic)
            if fileManager.fileExists(atPath: finalURL.path) {
                try fileManager.removeItem(at: finalURL)
            }
            try fileManager.moveItem(at: partialURL, to: finalURL)
            let entry = RangeEntry(range: sub, url: finalURL)
            let insertAt = state.entries.firstIndex(where: { $0.range.offset > sub.offset }) ?? state.entries.count
            state.entries.insert(entry, at: insertAt)
        }
    }

    // MARK: - Throttled index maintenance

    private func noteWrite(bytes: Int, key: MediaGatewayCacheKey) async throws {
        dirtyIndexKeys[storageID(for: key)] = key
        unsyncedWriteBytes += bytes
        let due = unsyncedWriteBytes >= configuration.indexSyncBytes
            || Date().timeIntervalSince(lastIndexSyncAt) >= configuration.indexSyncSeconds
        if due {
            try await syncIndexNow()
        }
    }

    private func syncIndexNow() async throws {
        // Active (dirty) keys are the ones being played/filled — never trim those out from under
        // the serve loop.
        let activeKeys = Set(dirtyIndexKeys.values)
        try await trim(budget: configuration.maxBytes, protectedKeys: activeKeys)
    }

    /// Persists index records for every key with unsynced writes, then resets the throttle window.
    private func flushIndexUpserts() async throws {
        defer {
            dirtyIndexKeys.removeAll()
            unsyncedWriteBytes = 0
            lastIndexSyncAt = Date()
        }
        guard !dirtyIndexKeys.isEmpty else { return }
        for key in dirtyIndexKeys.values {
            let size = (try? byteSize(for: key)) ?? 0
            try await index.upsert(key: key, byteSize: size, ttl: configuration.ttlSeconds)
        }
    }
}
