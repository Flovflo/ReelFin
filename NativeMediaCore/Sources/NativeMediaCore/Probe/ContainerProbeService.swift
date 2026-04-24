import Foundation

public enum ContainerFormat: String, Codable, Hashable, Sendable {
    case mp4
    case mov
    case matroska
    case webm
    case mpegTS
    case m2ts
    case avi
    case flv
    case ogg
    case unknown
}

public enum ProbeConfidence: String, Codable, Hashable, Sendable {
    case exactSignature
    case strong
    case hinted
    case unknown
}

public struct MediaContainerSignature: Equatable, Sendable {
    public var format: ContainerFormat
    public var confidence: ProbeConfidence
    public var reason: String

    public init(format: ContainerFormat, confidence: ProbeConfidence, reason: String) {
        self.format = format
        self.confidence = confidence
        self.reason = reason
    }
}

public struct ProbeResult: Equatable, Sendable {
    public var format: ContainerFormat
    public var confidence: ProbeConfidence
    public var mimeType: String?
    public var byteSignature: String
    public var reason: String

    public init(
        format: ContainerFormat,
        confidence: ProbeConfidence,
        mimeType: String? = nil,
        byteSignature: String,
        reason: String
    ) {
        self.format = format
        self.confidence = confidence
        self.mimeType = mimeType
        self.byteSignature = byteSignature
        self.reason = reason
    }
}

public struct ContainerProbeService: Sendable {
    public init() {}

    public func probe(source: any MediaByteSource, hint: String? = nil) async throws -> ProbeResult {
        let data = try await source.read(range: ByteRange(offset: 0, length: 4096))
        return probe(bytes: data, hint: hint)
    }

    public func probe(bytes: Data, hint: String? = nil, mimeType: String? = nil) -> ProbeResult {
        let signature = detect(bytes: bytes, hint: hint, mimeType: mimeType)
        return ProbeResult(
            format: signature.format,
            confidence: signature.confidence,
            mimeType: mimeType,
            byteSignature: prefixHex(bytes),
            reason: signature.reason
        )
    }

    public func detect(bytes: Data, hint: String? = nil, mimeType: String? = nil) -> MediaContainerSignature {
        if let exact = exactSignature(bytes) { return exact }
        if let mime = mimeType?.lowercased(), let format = formatFromHint(mime) {
            return MediaContainerSignature(format: format, confidence: .hinted, reason: "mime:\(mime)")
        }
        if let hint = hint?.lowercased(), let format = formatFromHint(hint) {
            return MediaContainerSignature(format: format, confidence: .hinted, reason: "hint:\(hint)")
        }
        return MediaContainerSignature(format: .unknown, confidence: .unknown, reason: "no recognized container signature")
    }

    private func exactSignature(_ bytes: Data) -> MediaContainerSignature? {
        let b = [UInt8](bytes.prefix(16))
        guard !b.isEmpty else { return nil }
        if b.starts(with: [0x1A, 0x45, 0xDF, 0xA3]) {
            return MediaContainerSignature(format: .matroska, confidence: .exactSignature, reason: "EBML header")
        }
        if b.count >= 12, String(bytes: b[4..<8], encoding: .ascii) == "ftyp" {
            return MediaContainerSignature(format: bmffFormat(b), confidence: .exactSignature, reason: "BMFF ftyp box")
        }
        if hasTSSync(bytes, packetSize: 188, syncOffset: 0) {
            return MediaContainerSignature(format: .mpegTS, confidence: .strong, reason: "MPEG-TS sync byte")
        }
        if hasTSSync(bytes, packetSize: 192, syncOffset: 4) {
            return MediaContainerSignature(format: .m2ts, confidence: .strong, reason: "M2TS sync byte with 4-byte prefix")
        }
        if b.starts(with: Array("RIFF".utf8)), b.count >= 12, String(bytes: b[8..<12], encoding: .ascii) == "AVI " {
            return MediaContainerSignature(format: .avi, confidence: .exactSignature, reason: "RIFF AVI header")
        }
        if b.starts(with: Array("FLV".utf8)) {
            return MediaContainerSignature(format: .flv, confidence: .exactSignature, reason: "FLV header")
        }
        if b.starts(with: Array("OggS".utf8)) {
            return MediaContainerSignature(format: .ogg, confidence: .exactSignature, reason: "Ogg page capture pattern")
        }
        return nil
    }

    private func bmffFormat(_ bytes: [UInt8]) -> ContainerFormat {
        let brand = bytes.count >= 12 ? String(bytes: bytes[8..<12], encoding: .ascii)?.lowercased() : nil
        if brand == "qt  " { return .mov }
        return .mp4
    }

    private func hasTSSync(_ bytes: Data, packetSize: Int, syncOffset: Int) -> Bool {
        guard bytes.count > syncOffset else { return false }
        guard bytes[bytes.index(bytes.startIndex, offsetBy: syncOffset)] == 0x47 else { return false }
        let second = syncOffset + packetSize
        guard bytes.count > second else { return true }
        return bytes[bytes.index(bytes.startIndex, offsetBy: second)] == 0x47
    }

    private func formatFromHint(_ value: String) -> ContainerFormat? {
        if value.contains("webm") { return .webm }
        if value.contains("mkv") || value.contains("matroska") { return .matroska }
        if value.contains("mp4") || value.contains("m4v") { return .mp4 }
        if value.contains("mov") || value.contains("quicktime") { return .mov }
        if value.contains("mpegts") || value.contains("mpeg-ts") || value.hasSuffix(".ts") { return .mpegTS }
        if value.contains("m2ts") { return .m2ts }
        if value.contains("avi") { return .avi }
        if value.contains("flv") { return .flv }
        if value.contains("ogg") || value.contains("ogv") { return .ogg }
        return nil
    }

    private func prefixHex(_ bytes: Data) -> String {
        bytes.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
