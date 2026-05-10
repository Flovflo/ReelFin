import Foundation

public enum PlayerDeepEvidenceSink {
    public static let fileName = "reelfin-player-deep-evidence.log"

    private static let lock = NSLock()
    private static var preparedProcessIdentifier: Int32?

    public static var isEnabled: Bool {
        let value = ProcessInfo.processInfo.environment["REELFIN_PLAYER_DEEP_EVIDENCE"] ?? ""
        return ["1", "true", "yes", "on"].contains(value.lowercased())
    }

    public static func append(_ line: String) {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }

        prepareFileIfNeeded()
        guard let url = evidenceFileURL() else { return }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            handle.write(Data("\(Self.timestamp()) \(line)\n".utf8))
        } catch {
            AppLog.playback.debug("player.deep.evidence.write_failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    public static func evidenceFileURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private static func prepareFileIfNeeded() {
        let processIdentifier = ProcessInfo.processInfo.processIdentifier
        guard preparedProcessIdentifier != processIdentifier else { return }
        preparedProcessIdentifier = processIdentifier

        let resetValue = ProcessInfo.processInfo.environment["REELFIN_PLAYER_DEEP_EVIDENCE_RESET"] ?? ""
        guard ["1", "true", "yes", "on"].contains(resetValue.lowercased()),
              let url = evidenceFileURL()
        else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
