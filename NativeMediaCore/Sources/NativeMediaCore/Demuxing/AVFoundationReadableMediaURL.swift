import Foundation

public final class AVFoundationReadableMediaURL: @unchecked Sendable {
    public let originalURL: URL
    public let assetURL: URL

    private let temporaryURL: URL?

    public init(originalURL: URL, format: ContainerFormat) throws {
        self.originalURL = originalURL
        guard originalURL.isFileURL, originalURL.pathExtension.isEmpty, let ext = Self.fileExtension(for: format) else {
            self.assetURL = originalURL
            self.temporaryURL = nil
            return
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("reelfin-avfoundation-media", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let linkedURL = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try FileManager.default.createSymbolicLink(at: linkedURL, withDestinationURL: originalURL)
        self.assetURL = linkedURL
        self.temporaryURL = linkedURL
    }

    deinit {
        if let temporaryURL {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
    }

    private static func fileExtension(for format: ContainerFormat) -> String? {
        switch format {
        case .mp4: return "mp4"
        case .mov: return "mov"
        default: return nil
        }
    }
}
