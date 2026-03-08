import Foundation

public struct WebVTTCue: Sendable, Equatable {
    public let identifier: String?
    public let start: String
    public let end: String
    public let payload: String

    public init(identifier: String?, start: String, end: String, payload: String) {
        self.identifier = identifier
        self.start = start
        self.end = end
        self.payload = payload
    }
}

public struct WebVTTDocument: Sendable, Equatable {
    public let cues: [WebVTTCue]

    public init(cues: [WebVTTCue]) {
        self.cues = cues
    }

    public var text: String {
        var lines: [String] = ["WEBVTT", ""]
        for cue in cues {
            if let identifier = cue.identifier, !identifier.isEmpty {
                lines.append(identifier)
            }
            lines.append("\(cue.start) --> \(cue.end)")
            lines.append(cue.payload)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

public enum SRTConversionError: Error, LocalizedError {
    case invalidTimestamp(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTimestamp(let line):
            return "Invalid SRT timestamp line: \(line)"
        }
    }
}

public struct SRTWebVTTConverter: Sendable {
    public init() {}

    public func convert(_ srt: String) throws -> WebVTTDocument {
        let normalized = srt
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let blocks = normalized
            .split(separator: "\n\n", omittingEmptySubsequences: true)
            .map(String.init)

        var cues: [WebVTTCue] = []
        cues.reserveCapacity(blocks.count)

        for block in blocks {
            let rawLines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard !rawLines.isEmpty else { continue }

            var lineIndex = 0
            var identifier: String?
            if !rawLines[lineIndex].contains("-->") {
                identifier = rawLines[lineIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                lineIndex += 1
            }

            guard lineIndex < rawLines.count else { continue }
            let timestampLine = rawLines[lineIndex]
            lineIndex += 1

            let (start, end) = try parseTimestampLine(timestampLine)
            let payloadLines = rawLines[lineIndex...]
                .map { sanitizePayloadLine($0) }
            let payload = payloadLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if payload.isEmpty { continue }

            cues.append(WebVTTCue(identifier: identifier, start: start, end: end, payload: payload))
        }

        return WebVTTDocument(cues: cues)
    }

    private func parseTimestampLine(_ line: String) throws -> (String, String) {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else {
            throw SRTConversionError.invalidTimestamp(line)
        }

        let start = normalizeTimestamp(parts[0])
        let end = normalizeTimestamp(parts[1])
        guard isTimestamp(start), isTimestamp(end) else {
            throw SRTConversionError.invalidTimestamp(line)
        }
        return (start, end)
    }

    private func normalizeTimestamp(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
    }

    private func isTimestamp(_ value: String) -> Bool {
        // hh:mm:ss.mmm
        let comps = value.split(separator: ":")
        guard comps.count == 3 else { return false }
        let secParts = comps[2].split(separator: ".")
        guard secParts.count == 2 else { return false }
        guard comps[0].count == 2, comps[1].count == 2, secParts[0].count == 2, secParts[1].count == 3 else {
            return false
        }
        return comps[0].allSatisfy(\.isNumber)
            && comps[1].allSatisfy(\.isNumber)
            && secParts[0].allSatisfy(\.isNumber)
            && secParts[1].allSatisfy(\.isNumber)
    }

    private func sanitizePayloadLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: "{\\i1}", with: "<i>")
            .replacingOccurrences(of: "{\\i0}", with: "</i>")
            .replacingOccurrences(of: "{\\b1}", with: "<b>")
            .replacingOccurrences(of: "{\\b0}", with: "</b>")
    }
}
