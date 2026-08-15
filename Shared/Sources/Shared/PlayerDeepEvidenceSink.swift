import Foundation

public enum PlayerDeepEvidenceEvent: String, CaseIterable, Sendable {
    case plan
    case routeSelection
    case audioSelection
    case firstFrame
    case ttff
    case avPlayerTick
    case playbackProof
    case sampleBufferTick
}

public enum PlayerDeepEvidenceField: String, CaseIterable, Hashable, Sendable {
    case canStart
    case demuxer
    case videoBackend
    case audioBackend
    case route
    case avPlayerItem
    case avPlayerViewController
    case serverTranscodeUsed
    case codec
    case isDefault
    case elapsedMilliseconds
    case currentSeconds
    case totalMilliseconds
    case infoMilliseconds
    case resolveMilliseconds
    case readyMilliseconds
    case playerMilliseconds
    case method
    case profile
    case videoIntegrity
    case hdrIntegrity
    case deltaSeconds
    case rate
    case timeControl
    case itemStatus
    case likelyToKeepUp
    case bufferedSeconds
    case droppedFrames
    case observedBitrate
    case accessObservedBitrate
    case accessIndicatedBitrate
    case accessStalls
    case accessTransferSeconds
    case width
    case height
    case bitDepth
    case hdr
    case dolbyVision
    case sourceBitrate
    case container
    case dolbyVisionProfile
    case dolbyVisionLevel
    case videoRange
    case state
    case videoPackets
    case audioPackets
    case audioSamples
    case audioRenderer
    case audioUnderruns
    case audioRebuffers
    case avDriftMilliseconds
}

public enum PlayerDeepEvidenceCategory: String, CaseIterable, Sendable {
    case unknown
    case none
    case directPlay
    case directStream
    case transcode
    case native
    case avPlayer
    case sampleBuffer
    case matroska
    case mp4
    case mpegts
    case videoToolbox
    case sampleBufferAudioRenderer
    case hevc
    case hvc1
    case h264
    case avc1
    case eac3
    case ac3
    case aac
    case truehd
    case opus
    case flac
    case playing
    case paused
    case waiting
    case readyToPlay
    case failed
    case pq
    case hlg
    case sdr
    case hdr10
    case dolbyVision
    case originalVideo
    case originalHDR
    case watchableSDR
    case preserved
    case converted
    case unavailable

    public static func normalized(_ value: String?) -> Self {
        switch value?.lowercased() {
        case "directplay", "direct_play": .directPlay
        case "directstream", "direct_stream": .directStream
        case "transcode", "transcoding": .transcode
        case "native": .native
        case "avplayer": .avPlayer
        case "samplebuffer", "sample_buffer": .sampleBuffer
        case "matroska", "mkv", "matroskademuxer": .matroska
        case "mp4", "mov": .mp4
        case "mpegts", "mpeg-ts", "ts": .mpegts
        case "videotoolbox": .videoToolbox
        case "avsamplebufferaudiorenderer", "samplebufferaudiorenderer": .sampleBufferAudioRenderer
        case "hevc": .hevc
        case "hvc1", "hev1": .hvc1
        case "h264": .h264
        case "avc1": .avc1
        case "eac3", "e-ac-3", "ec-3": .eac3
        case "ac3", "ac-3": .ac3
        case "aac", "mp4a": .aac
        case "truehd", "mlp": .truehd
        case "opus": .opus
        case "flac": .flac
        case "playing": .playing
        case "paused": .paused
        case "waiting", "waitingtoplayatspecifiedrate": .waiting
        case "readytoplay": .readyToPlay
        case "failed": .failed
        case "pq", "smpte2084": .pq
        case "hlg": .hlg
        case "sdr": .sdr
        case "hdr10": .hdr10
        case "dolbyvision", "dv": .dolbyVision
        case "originalvideo": .originalVideo
        case "originalhdr": .originalHDR
        case "watchablesdr": .watchableSDR
        case "preserved": .preserved
        case "converted": .converted
        case "unavailable", "missing": .unavailable
        case "none", "n/a": .none
        default: .unknown
        }
    }
}

public enum PlayerDeepEvidenceValue: Sendable, Equatable {
    case boolean(Bool)
    case integer(Int64)
    case decimal(Double)
    case category(PlayerDeepEvidenceCategory)
}

public enum PlayerDeepEvidenceRecordError: Error, Equatable {
    case invalidSessionCorrelation
    case invalidMediaCorrelation
    case invalidSourceCorrelation
    case fieldNotAllowed
    case nonFiniteDecimal
}

public struct PlayerDeepEvidenceRecord: Sendable {
    public let event: PlayerDeepEvidenceEvent
    public let session: String
    public let media: String?
    public let source: String?
    public let fields: [PlayerDeepEvidenceField: PlayerDeepEvidenceValue]

    public init(
        event: PlayerDeepEvidenceEvent,
        session: String,
        media: String? = nil,
        source: String? = nil,
        fields: [PlayerDeepEvidenceField: PlayerDeepEvidenceValue]
    ) throws {
        guard Self.isOpaqueCorrelation(session) else {
            throw PlayerDeepEvidenceRecordError.invalidSessionCorrelation
        }
        if let media, !Self.isOpaqueCorrelation(media) {
            throw PlayerDeepEvidenceRecordError.invalidMediaCorrelation
        }
        if let source, !Self.isOpaqueCorrelation(source) {
            throw PlayerDeepEvidenceRecordError.invalidSourceCorrelation
        }
        guard Set(fields.keys).isSubset(of: event.allowedFields) else {
            throw PlayerDeepEvidenceRecordError.fieldNotAllowed
        }
        guard fields.values.allSatisfy({ value in
            guard case let .decimal(decimal) = value else { return true }
            return decimal.isFinite
        }) else {
            throw PlayerDeepEvidenceRecordError.nonFiniteDecimal
        }
        self.event = event
        self.session = session
        self.media = media
        self.source = source
        self.fields = fields
    }

    fileprivate func encodedLine(timestampMilliseconds: Int64) throws -> Data {
        var object: [String: Any] = [
            "event": event.rawValue,
            "session": session,
            "timestampMilliseconds": timestampMilliseconds,
        ]
        if let media { object["media"] = media }
        if let source { object["source"] = source }
        for (field, value) in fields {
            switch value {
            case let .boolean(boolean): object[field.rawValue] = boolean
            case let .integer(integer): object[field.rawValue] = integer
            case let .decimal(decimal): object[field.rawValue] = decimal
            case let .category(category): object[field.rawValue] = category.rawValue
            }
        }
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }

    private static func isOpaqueCorrelation(_ value: String) -> Bool {
        value.utf8.count == 16 && value.utf8.allSatisfy { byte in
            (48 ... 57).contains(byte) || (97 ... 102).contains(byte)
        }
    }
}

private extension PlayerDeepEvidenceEvent {
    var allowedFields: Set<PlayerDeepEvidenceField> {
        switch self {
        case .plan:
            [.canStart, .demuxer, .videoBackend, .audioBackend]
        case .routeSelection:
            [.route, .avPlayerItem, .avPlayerViewController, .serverTranscodeUsed]
        case .audioSelection:
            [.codec, .isDefault]
        case .firstFrame:
            [.elapsedMilliseconds, .currentSeconds]
        case .ttff:
            [
                .totalMilliseconds, .infoMilliseconds, .resolveMilliseconds, .readyMilliseconds,
                .playerMilliseconds, .method, .profile, .route, .videoIntegrity, .hdrIntegrity,
            ]
        case .avPlayerTick:
            [
                .currentSeconds, .deltaSeconds, .rate, .timeControl, .itemStatus, .likelyToKeepUp,
                .bufferedSeconds, .droppedFrames, .observedBitrate, .accessObservedBitrate,
                .accessIndicatedBitrate, .accessStalls, .accessTransferSeconds, .codec, .method,
            ]
        case .playbackProof:
            [
                .width, .height, .codec, .bitDepth, .hdr, .dolbyVision, .method, .profile,
                .sourceBitrate, .container, .dolbyVisionProfile, .dolbyVisionLevel, .videoRange,
                .observedBitrate,
            ]
        case .sampleBufferTick:
            [
                .currentSeconds, .deltaSeconds, .state, .videoPackets, .audioPackets, .audioSamples,
                .audioRenderer, .droppedFrames, .audioUnderruns, .audioRebuffers,
                .avDriftMilliseconds, .hdr, .dolbyVisionProfile,
            ]
        }
    }
}

public enum PlayerDeepEvidenceFailureCategory: String, Sendable {
    case createDirectory
    case setDirectoryAttributes
    case reset
    case createFile
    case setFileAttributes
    case inspectFile
    case encode
    case openFile
    case write
}

public enum PlayerDeepEvidenceAppendResult: Sendable, Equatable {
    case written
    case disabled
    case rejectedOversized
    case failed(PlayerDeepEvidenceFailureCategory)
}

public final class PlayerDeepEvidenceStore: @unchecked Sendable {
    public static let fileProtection = FileProtectionType.complete
    private let fileURL: URL
    private let enabled: Bool
    private let maxBytes: Int
    private let resetOnFirstAppend: Bool
    private let fileManager: FileManager
    private let lock = NSLock()
    private var hasPrepared = false

    public init(
        fileURL: URL,
        enabled: Bool,
        maxBytes: Int = 1_048_576,
        resetOnFirstAppend: Bool,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.enabled = enabled
        self.maxBytes = max(0, maxBytes)
        self.resetOnFirstAppend = resetOnFirstAppend
        self.fileManager = fileManager
    }

    public func append(_ record: PlayerDeepEvidenceRecord) -> PlayerDeepEvidenceAppendResult {
        guard enabled else { return .disabled }
        lock.lock()
        defer { lock.unlock() }

        let encoded: Data
        do {
            encoded = try record.encodedLine(timestampMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000))
        } catch {
            return .failed(.encode)
        }
        guard encoded.count <= maxBytes else { return .rejectedOversized }

        if !hasPrepared {
            hasPrepared = true
            if resetOnFirstAppend, fileManager.fileExists(atPath: fileURL.path) {
                do { try fileManager.removeItem(at: fileURL) } catch { return .failed(.reset) }
            }
        }
        if let failure = prepareDirectory() { return .failed(failure) }

        let existingSize: Int
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                existingSize = (try fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue ?? 0
            } catch {
                return .failed(.inspectFile)
            }
        } else {
            existingSize = 0
        }

        if existingSize > maxBytes - encoded.count {
            do { try fileManager.removeItem(at: fileURL) } catch { return .failed(.reset) }
        }
        if let failure = prepareFile() { return .failed(failure) }

        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: encoded)
            return .written
        } catch {
            return .failed(.write)
        }
    }

    private func prepareDirectory() -> PlayerDeepEvidenceFailureCategory? {
        let directoryURL = fileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700, .protectionKey: Self.fileProtection]
            )
        } catch {
            return .createDirectory
        }
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o700, .protectionKey: Self.fileProtection],
                ofItemAtPath: directoryURL.path
            )
        } catch {
            return .setDirectoryAttributes
        }
        return nil
    }

    private func prepareFile() -> PlayerDeepEvidenceFailureCategory? {
        if !fileManager.fileExists(atPath: fileURL.path) {
            guard fileManager.createFile(
                atPath: fileURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600, .protectionKey: Self.fileProtection]
            ) else {
                return .createFile
            }
        }
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o600, .protectionKey: Self.fileProtection],
                ofItemAtPath: fileURL.path
            )
        } catch {
            return .setFileAttributes
        }
        return nil
    }
}

public enum PlayerDeepEvidenceSink {
    public static let fileName = "reelfin-player-deep-evidence.jsonl"
    public static let maximumTotalBytes = 1_048_576
    public static let fileProtection = PlayerDeepEvidenceStore.fileProtection

    private static let store = PlayerDeepEvidenceStore(
        fileURL: evidenceFileURL(),
        enabled: isEnabled(environment: ProcessInfo.processInfo.environment),
        maxBytes: maximumTotalBytes,
        resetOnFirstAppend: resetRequested(environment: ProcessInfo.processInfo.environment)
    )

    public static func isEnabled(environment: [String: String]) -> Bool {
        truthy(environment["REELFIN_PLAYER_DEEP_EVIDENCE"])
    }

    public static var isEnabled: Bool {
        isEnabled(environment: ProcessInfo.processInfo.environment)
    }

    public static func append(_ record: PlayerDeepEvidenceRecord) {
        switch store.append(record) {
        case .written, .disabled: break
        case .rejectedOversized:
            AppLog.playback.debug("player.deep.evidence.write_failed category=oversized_record")
        case let .failed(category):
            AppLog.playback.debug("player.deep.evidence.write_failed category=\(category.rawValue, privacy: .public)")
        }
    }

    public static func append(
        event: PlayerDeepEvidenceEvent,
        session: String,
        media: String? = nil,
        source: String? = nil,
        fields: [PlayerDeepEvidenceField: PlayerDeepEvidenceValue]
    ) {
        do {
            append(
                try PlayerDeepEvidenceRecord(
                    event: event,
                    session: session,
                    media: media,
                    source: source,
                    fields: fields
                )
            )
        } catch {
            AppLog.playback.debug("player.deep.evidence.write_failed category=invalid_record")
        }
    }

    public static func evidenceFileURL(cachesDirectory: URL? = nil) -> URL {
        let caches = cachesDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches
            .appendingPathComponent("ReelFin", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private static func resetRequested(environment: [String: String]) -> Bool {
        truthy(environment["REELFIN_PLAYER_DEEP_EVIDENCE_RESET"])
    }

    private static func truthy(_ value: String?) -> Bool {
        ["1", "true", "yes", "on"].contains(value?.lowercased() ?? "")
    }
}
