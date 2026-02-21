import CryptoKit
import Foundation

public actor LRUDiskCache {
    struct Entry: Codable {
        var fileName: String
        var size: Int
        var lastAccess: Date
    }

    private let directoryURL: URL
    private let indexURL: URL
    private let maxSizeBytes: Int
    private let fileManager: FileManager

    private var entries: [String: Entry] = [:]
    private var currentSizeBytes: Int = 0

    public init(
        directoryURL: URL? = nil,
        maxSizeBytes: Int = 350 * 1_024 * 1_024,
        fileManager: FileManager = .default
    ) throws {
        self.fileManager = fileManager
        self.maxSizeBytes = maxSizeBytes

        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let cacheRoot = try fileManager.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.directoryURL = cacheRoot.appendingPathComponent("ReelFinImageCache", isDirectory: true)
        }

        self.indexURL = self.directoryURL.appendingPathComponent("index.json")

        if !fileManager.fileExists(atPath: self.directoryURL.path) {
            try fileManager.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
        }

        loadIndex()
    }

    public func data(forKey key: String) -> Data? {
        guard var entry = entries[key] else {
            return nil
        }

        let fileURL = directoryURL.appendingPathComponent(entry.fileName)
        guard let data = try? Data(contentsOf: fileURL) else {
            entries[key] = nil
            persistIndex()
            return nil
        }

        entry.lastAccess = Date()
        entries[key] = entry
        persistIndex()
        return data
    }

    public func setData(_ data: Data, forKey key: String) {
        let fileName = hash(key)
        let fileURL = directoryURL.appendingPathComponent(fileName)

        if let existing = entries[key] {
            currentSizeBytes -= existing.size
        }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }

        let entry = Entry(fileName: fileName, size: data.count, lastAccess: Date())
        entries[key] = entry
        currentSizeBytes += data.count

        trimIfNeeded()
        persistIndex()
    }

    public func remove(forKey key: String) {
        guard let entry = entries[key] else { return }

        let fileURL = directoryURL.appendingPathComponent(entry.fileName)
        try? fileManager.removeItem(at: fileURL)
        currentSizeBytes -= entry.size
        entries[key] = nil
        persistIndex()
    }

    public func removeAll() {
        for entry in entries.values {
            let fileURL = directoryURL.appendingPathComponent(entry.fileName)
            try? fileManager.removeItem(at: fileURL)
        }

        entries.removeAll()
        currentSizeBytes = 0
        persistIndex()
    }

    public func entryCount() -> Int {
        entries.count
    }

    private func trimIfNeeded() {
        guard currentSizeBytes > maxSizeBytes else { return }

        let sorted = entries.sorted { $0.value.lastAccess < $1.value.lastAccess }
        for (key, entry) in sorted {
            guard currentSizeBytes > maxSizeBytes else { break }

            let fileURL = directoryURL.appendingPathComponent(entry.fileName)
            try? fileManager.removeItem(at: fileURL)
            currentSizeBytes -= entry.size
            entries[key] = nil
        }
    }

    private func loadIndex() {
        guard
            let data = try? Data(contentsOf: indexURL),
            let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else {
            entries = [:]
            currentSizeBytes = 0
            return
        }

        entries = decoded
        currentSizeBytes = decoded.values.reduce(0) { $0 + $1.size }
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func hash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
