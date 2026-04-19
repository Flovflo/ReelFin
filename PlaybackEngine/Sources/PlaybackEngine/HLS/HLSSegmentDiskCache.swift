import CryptoKit
import Foundation

public actor HLSSegmentDiskCache {
    public enum ArtifactKind: String, Codable, CaseIterable, Sendable {
        case masterPlaylist
        case mediaPlaylist
        case initSegment
        case mediaSegment

        fileprivate var filePrefix: String {
            switch self {
            case .masterPlaylist: return "master-playlist"
            case .mediaPlaylist: return "media-playlist"
            case .initSegment: return "init-segment"
            case .mediaSegment: return "media-segment"
            }
        }
    }

    public struct Key: Hashable, Sendable {
        public let kind: ArtifactKind
        public let identifier: String

        public init(kind: ArtifactKind, identifier: String) {
            self.kind = kind
            self.identifier = identifier
        }

        public init(kind: ArtifactKind, url: URL) {
            self.init(kind: kind, identifier: url.absoluteString)
        }
    }

    private struct Entry: Codable {
        var fileName: String
        var size: Int
        var lastAccess: Date
        var expiresAt: Date?
        var kind: ArtifactKind
    }

    private let directoryURL: URL
    private let indexURL: URL
    private let maxSizeBytes: Int
    private let ttl: TimeInterval?
    private let fileManager: FileManager
    private var entries: [String: Entry]
    private var storedSizeBytes: Int
    private var lastIssuedTimestamp: Date?

    public init(
        directoryURL: URL? = nil,
        maxSizeBytes: Int = 16 * 1024 * 1024,
        ttl: TimeInterval? = nil,
        fileManager: FileManager = .default
    ) throws {
        self.fileManager = fileManager
        self.maxSizeBytes = max(1, maxSizeBytes)
        self.ttl = ttl.flatMap { $0 > 0 ? $0 : nil }

        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let cacheRoot = try fileManager.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.directoryURL = cacheRoot.appendingPathComponent("ReelFinHLSSegmentCache", isDirectory: true)
        }

        self.indexURL = self.directoryURL.appendingPathComponent("index.json")

        if !fileManager.fileExists(atPath: self.directoryURL.path) {
            try fileManager.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
        }

        let recoveredEntries = try Self.loadEntries(
            from: self.directoryURL,
            indexURL: self.indexURL,
            fileManager: fileManager,
            ttl: self.ttl
        )
        self.entries = recoveredEntries.entries
        self.storedSizeBytes = recoveredEntries.currentSizeBytes
        self.lastIssuedTimestamp = recoveredEntries.entries.values.map(\.lastAccess).max()
        if let data = try? JSONEncoder().encode(recoveredEntries.entries) {
            try? data.write(to: self.indexURL, options: .atomic)
        }
    }

    public func data(for key: Key) -> Data? {
        purgeExpiredEntries(now: Date())

        let digest = digest(for: key)
        guard var entry = entries[digest] else {
            return nil
        }

        let fileURL = directoryURL.appendingPathComponent(entry.fileName)
        guard let data = try? Data(contentsOf: fileURL) else {
            removeEntry(digest)
            persistIndex()
            return nil
        }

        let now = nextTimestamp()
        entry.lastAccess = now
        if let ttl {
            entry.expiresAt = now.addingTimeInterval(ttl)
        }
        entries[digest] = entry
        touchFile(at: fileURL, date: now)
        persistIndex()
        return data
    }

    public func setData(_ data: Data, for key: Key) {
        purgeExpiredEntries(now: Date())

        let digest = digest(for: key)
        let fileName = fileName(for: key, digest: digest)
        let fileURL = directoryURL.appendingPathComponent(fileName)
        let previousEntry = entries[digest]

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }

        let now = nextTimestamp()
        let expiry = ttl.map { now.addingTimeInterval($0) }

        if let previousEntry {
            storedSizeBytes -= previousEntry.size
        }

        entries[digest] = Entry(
            fileName: fileName,
            size: data.count,
            lastAccess: now,
            expiresAt: expiry,
            kind: key.kind
        )
        storedSizeBytes += data.count
        touchFile(at: fileURL, date: now)
        trimIfNeeded()
        persistIndex()
    }

    public func remove(for key: Key) {
        let digest = digest(for: key)
        removeEntry(digest)
        persistIndex()
    }

    public func removeAll() {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        for url in urls where url.lastPathComponent == "index.json" || url.lastPathComponent.hasSuffix(".cache") {
            try? fileManager.removeItem(at: url)
        }
        entries.removeAll()
        storedSizeBytes = 0
        lastIssuedTimestamp = nil
        persistIndex()
    }

    public func entryCount() -> Int {
        purgeExpiredEntries(now: Date())
        return entries.count
    }

    public func currentSizeBytes() -> Int {
        purgeExpiredEntries(now: Date())
        return storedSizeBytes
    }

    private func trimIfNeeded() {
        guard storedSizeBytes > maxSizeBytes else { return }

        let orderedEntries = entries
            .sorted {
                if $0.value.lastAccess != $1.value.lastAccess {
                    return $0.value.lastAccess < $1.value.lastAccess
                }
                return $0.key < $1.key
            }

        for (digest, _) in orderedEntries {
            guard storedSizeBytes > maxSizeBytes else { break }
            removeEntry(digest)
        }
    }

    private func purgeExpiredEntries(now: Date) {
        guard entries.isEmpty == false else { return }
        let expiredDigests = entries.compactMap { digest, entry -> String? in
            guard let expiresAt = entry.expiresAt, expiresAt <= now else { return nil }
            return digest
        }
        guard !expiredDigests.isEmpty else { return }
        for digest in expiredDigests {
            removeEntry(digest)
        }
        persistIndex()
    }

    private func removeEntry(_ digest: String) {
        guard let entry = entries.removeValue(forKey: digest) else { return }
        let fileURL = directoryURL.appendingPathComponent(entry.fileName)
        try? fileManager.removeItem(at: fileURL)
        storedSizeBytes = max(0, storedSizeBytes - entry.size)
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func touchFile(at url: URL, date: Date) {
        try? fileManager.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func digest(for key: Key) -> String {
        let payload = "\(key.kind.rawValue)\u{0}\(key.identifier)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func fileName(for key: Key, digest: String) -> String {
        "\(key.kind.filePrefix)-\(digest).cache"
    }

    private static func loadEntries(
        from directoryURL: URL,
        indexURL: URL,
        fileManager: FileManager,
        ttl: TimeInterval?
    ) throws -> (entries: [String: Entry], currentSizeBytes: Int) {
        let diskFiles = try Self.readDiskFiles(in: directoryURL, fileManager: fileManager, ttl: ttl)

        let indexEntries: [String: Entry]
        if
            let data = try? Data(contentsOf: indexURL),
            let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        {
            indexEntries = decoded
        } else {
            indexEntries = [:]
        }

        var recovered: [String: Entry] = [:]

        for (digest, entry) in indexEntries {
            guard let file = diskFiles[entry.fileName] else { continue }
            let lastAccess = max(entry.lastAccess, file.entry.lastAccess)
            let expiresAt = entry.expiresAt ?? file.entry.expiresAt ?? ttl.map { lastAccess.addingTimeInterval($0) }
            recovered[digest] = Entry(
                fileName: file.fileName,
                size: file.entry.size,
                lastAccess: lastAccess,
                expiresAt: expiresAt,
                kind: entry.kind
            )
        }

        for file in diskFiles.values {
            guard recovered[file.digest] == nil else { continue }
            recovered[file.digest] = file.entry
        }

        var filtered = recovered
        if ttl != nil {
            let now = Date()
            filtered = filtered.filter { _, entry in
                guard let expiresAt = entry.expiresAt else { return true }
                return expiresAt > now
            }
        }

        let currentSizeBytes = filtered.values.reduce(0) { $0 + $1.size }
        return (filtered, currentSizeBytes)
    }

    private static func readDiskFiles(
        in directoryURL: URL,
        fileManager: FileManager,
        ttl: TimeInterval?
    ) throws -> [String: DiskFile] {
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var files: [String: DiskFile] = [:]
        for url in urls where url.lastPathComponent != "index.json" {
            guard let parsed = DiskFile(url: url, fileManager: fileManager, ttl: ttl) else { continue }
            files[parsed.fileName] = parsed
        }
        return files
    }

    private struct DiskFile {
        let fileName: String
        let digest: String
        let entry: Entry

        init?(url: URL, fileManager: FileManager, ttl: TimeInterval?) {
            let fileName = url.lastPathComponent
            guard let (kind, digest) = Self.parse(fileName: fileName) else { return nil }

            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let size = max(0, (attributes?[.size] as? NSNumber)?.intValue ?? 0)
            let modificationDate = (attributes?[.modificationDate] as? Date) ?? Date()
            let expiresAt = ttl.map { modificationDate.addingTimeInterval($0) }

            self.fileName = fileName
            self.digest = digest
            self.entry = Entry(
                fileName: "\(kind.filePrefix)-\(digest).cache",
                size: size,
                lastAccess: modificationDate,
                expiresAt: expiresAt,
                kind: kind
            )
        }

        private static func parse(fileName: String) -> (ArtifactKind, String)? {
            guard fileName.hasSuffix(".cache") else { return nil }
            let stem = String(fileName.dropLast(".cache".count))
            guard let separator = stem.lastIndex(of: "-") else { return nil }

            let prefix = String(stem[..<separator])
            let digest = String(stem[stem.index(after: separator)...])
            guard let kind = ArtifactKind.allCases.first(where: { $0.filePrefix == prefix }), digest.count == 64 else {
                return nil
            }

            return (kind, digest)
        }
    }

    private func nextTimestamp() -> Date {
        let now = Date()
        guard let lastIssued = lastIssuedTimestamp, now <= lastIssued else {
            lastIssuedTimestamp = now
            return now
        }

        let bumped = lastIssued.addingTimeInterval(0.000001)
        lastIssuedTimestamp = bumped
        return bumped
    }
}
