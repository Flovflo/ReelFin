import Foundation
import Shared

public final class FileNativeBridgeDebugBundleExporter: NativeBridgeDebugBundleExporter {
    public init() {}

    public func export(bundle: NativeBridgeDebugBundle) throws -> URL {
        let metadataURL = (bundle.initSegmentURL?.deletingLastPathComponent()
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("bundle.json")
        let payload: [String: Any] = [
            "itemID": bundle.itemID,
            "createdAt": ISO8601DateFormatter().string(from: bundle.createdAt),
            "initSegmentURL": bundle.initSegmentURL?.path as Any,
            "fragmentURLs": bundle.fragmentURLs.map(\.path),
            "requestTrace": bundle.requestTrace.map {
                [
                    "offset": $0.requestedOffset,
                    "length": $0.requestedLength,
                    "startedAt": ISO8601DateFormatter().string(from: $0.startedAt),
                    "finishedAt": $0.finishedAt.map { ISO8601DateFormatter().string(from: $0) } as Any
                ]
            },
            "fragmentTrace": bundle.fragmentTrace.map {
                [
                    "sequenceNumber": $0.sequenceNumber,
                    "moofSize": $0.moofSize,
                    "mdatSize": $0.mdatSize,
                    "sampleCount": $0.sampleCount,
                    "firstPTS": $0.firstPTS
                ]
            },
            "trackDump": bundle.trackDump
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: metadataURL, options: .atomic)
        return metadataURL
    }
}

public actor NativeBridgeDiagnosticsCollector {
    private let config: NativeBridgeDiagnosticsConfig
    private var initSegmentURL: URL?
    private var fragmentURLs: [URL] = []
    private var requestTrace: [UUID: NativeBridgeRequestTraceEntry] = [:]
    private var requestOrder: [UUID] = []
    private var fragmentTrace: [NativeBridgeFragmentTraceEntry] = []

    public init(config: NativeBridgeDiagnosticsConfig) {
        self.config = config
    }

    public var isEnabled: Bool {
        config.enabled
    }

    public func recordRequestStart(offset: Int64, length: Int) -> UUID? {
        guard config.enabled else { return nil }
        let token = UUID()
        requestTrace[token] = NativeBridgeRequestTraceEntry(
            requestedOffset: offset,
            requestedLength: length,
            startedAt: Date(),
            finishedAt: nil
        )
        requestOrder.append(token)
        return token
    }

    public func recordRequestFinish(_ token: UUID?) {
        guard config.enabled, let token, let entry = requestTrace[token] else { return }
        requestTrace[token] = NativeBridgeRequestTraceEntry(
            requestedOffset: entry.requestedOffset,
            requestedLength: entry.requestedLength,
            startedAt: entry.startedAt,
            finishedAt: Date()
        )
    }

    public func recordInitSegment(_ data: Data) {
        guard config.enabled else { return }
        AppLog.nativeBridge.debug("Diagnostics init segment size=\(data.count)")
        guard config.dumpSegments else { return }
        initSegmentURL = writeDumpFile(name: "init.mp4", data: data)
    }

    public func recordFragment(sequenceNumber: Int, fragment: Data, moofSize: Int, mdatSize: Int, sampleCount: Int, firstPTS: Int64) {
        guard config.enabled else { return }
        fragmentTrace.append(
            NativeBridgeFragmentTraceEntry(
                sequenceNumber: sequenceNumber,
                moofSize: moofSize,
                mdatSize: mdatSize,
                sampleCount: sampleCount,
                firstPTS: firstPTS
            )
        )
        AppLog.nativeBridge.debug(
            "Diagnostics fragment #\(sequenceNumber) moof=\(moofSize) mdat=\(mdatSize) samples=\(sampleCount)"
        )
        guard config.dumpSegments else { return }
        guard fragmentURLs.count < config.maxFragmentDumpCount else { return }
        if let url = writeDumpFile(name: "fragment_\(sequenceNumber).mp4", data: fragment) {
            fragmentURLs.append(url)
        }
    }

    public func snapshot(itemID: String, trackDump: String) -> NativeBridgeDebugBundle? {
        guard config.enabled else { return nil }
        let orderedTrace = requestOrder.compactMap { requestTrace[$0] }
        return NativeBridgeDebugBundle(
            itemID: itemID,
            initSegmentURL: initSegmentURL,
            fragmentURLs: fragmentURLs,
            requestTrace: orderedTrace,
            fragmentTrace: fragmentTrace,
            trackDump: trackDump
        )
    }

    private func writeDumpFile(name: String, data: Data) -> URL? {
        #if DEBUG
        let directory = config.outputDirectoryURL ?? defaultOutputDirectory()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            let url = directory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            AppLog.nativeBridge.error("Failed to write diagnostics dump: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        #else
        _ = (name, data)
        return nil
        #endif
    }

    private func defaultOutputDirectory() -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("NativeBridgeDiagnostics", isDirectory: true)
            .appendingPathComponent(DateFormatter.nativeBridgeDiagnosticsTimestamp.string(from: Date()), isDirectory: true)
    }
}

private extension DateFormatter {
    static let nativeBridgeDiagnosticsTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
}
