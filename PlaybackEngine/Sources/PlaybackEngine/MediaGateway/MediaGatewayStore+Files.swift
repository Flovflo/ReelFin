import CryptoKit
import Foundation
import NativeMediaCore

extension MediaGatewayStore {
    struct RangeEntry {
        let range: ByteRange
        let url: URL
    }

    /// A slice of one on-disk segment file: read `lengthInFile` bytes starting at `offsetInFile`.
    struct CoveredChunk {
        let url: URL
        let offsetInFile: Int64
        let lengthInFile: Int
    }

    /// Maps a requested byte range onto the given (sorted) entries. Returns [] unless the whole
    /// range is covered. Pure function over the in-memory coverage — no disk access.
    func coveredChunks(for range: ByteRange, entries: [RangeEntry]) -> [CoveredChunk] {
        var cursor = range.offset
        let end = range.offset + Int64(range.length)
        var chunks: [CoveredChunk] = []

        for entry in entries {
            let lower = max(cursor, entry.range.offset)
            let upper = min(end, entry.range.offset + Int64(entry.range.length))
            guard lower < upper else { continue }
            guard lower == cursor else { break } // gap before this entry → not fully covered
            chunks.append(CoveredChunk(url: entry.url, offsetInFile: lower - entry.range.offset, lengthInFile: Int(upper - lower)))
            cursor = upper
            if cursor >= end { break }
        }

        return cursor >= end ? chunks : []
    }

    /// Reads exactly the requested slice of a segment file (never the whole file — segment files
    /// are up to `segmentMaxBytes`, and loading 32MB to serve a 4MB chunk was 8× read
    /// amplification on the serve hot path).
    func readSlice(url: URL, offsetInFile: Int64, length: Int) throws -> Data {
        guard length > 0 else { return Data() }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(max(0, offsetInFile)))
        guard let data = try handle.read(upToCount: length), data.count == length else {
            throw MediaAccessError.cannotDetermineSize
        }
        return data
    }

    /// One-time disk scan for a key — the in-memory coverage cache is initialized from this, then
    /// maintained by mutations. Never called on the serve/write hot path.
    func scanRangeEntriesFromDisk(for key: MediaGatewayCacheKey) throws -> [RangeEntry] {
        let directory = directoryURL(for: key)
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [URLResourceKey.fileSizeKey])
        return urls.compactMap(rangeEntry).sorted { $0.range.offset < $1.range.offset }
    }

    func rangeEntry(from url: URL) -> RangeEntry? {
        guard url.pathExtension == "cache" else { return nil }
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-")
        guard parts.count == 3,
              parts[0] == "range",
              let offset = Int64(parts[1]),
              let length = Int(parts[2]),
              length > 0 else { return nil }
        return RangeEntry(range: ByteRange(offset: offset, length: length), url: url)
    }

    func removeKey(_ key: MediaGatewayCacheKey) throws {
        let directory = directoryURL(for: key)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        invalidateState(for: key)
    }

    func fileURL(for range: ByteRange, key: MediaGatewayCacheKey) -> URL {
        directoryURL(for: key)
            .appendingPathComponent("range-\(range.offset)-\(range.length)")
            .appendingPathExtension("cache")
    }

    func partialURL(for range: ByteRange, key: MediaGatewayCacheKey) -> URL {
        fileURL(for: range, key: key).appendingPathExtension("part")
    }

    func directoryURL(for key: MediaGatewayCacheKey) -> URL {
        rootURL.appendingPathComponent(storageID(for: key), isDirectory: true)
    }

    func storageID(for key: MediaGatewayCacheKey) -> String {
        let hash = SHA256.hash(data: Data(key.storageIdentity.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    func coalesced(_ ranges: [ByteRange]) -> [ByteRange] {
        let sorted = ranges.sorted { $0.offset < $1.offset }
        return sorted.reduce(into: []) { result, range in
            guard let last = result.last else {
                result.append(range)
                return
            }
            let lastEnd = last.offset + Int64(last.length)
            if range.offset <= lastEnd {
                result[result.count - 1].length = Int(max(lastEnd, range.offset + Int64(range.length)) - last.offset)
            } else {
                result.append(range)
            }
        }
    }

    func matches(_ key: MediaGatewayCacheKey, serverID: String?, userID: String?) -> Bool {
        if let serverID, key.serverID != serverID { return false }
        if let userID, key.userID != userID { return false }
        return true
    }

    static func defaultRootDirectoryURL(fileManager: FileManager) -> URL {
        let cacheRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return cacheRoot.appendingPathComponent("ReelFinMediaGatewayStore", isDirectory: true)
    }
}
