import CoreMedia
import Foundation

public struct SRTParser: SubtitleParser {
    public init() {}

    public func parse(_ data: Data) throws -> [SubtitleCue] {
        let text = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return text.components(separatedBy: "\n\n").compactMap(parseBlock)
    }

    private func parseBlock(_ block: String) -> SubtitleCue? {
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 2 else { return nil }
        let timingIndex = lines.firstIndex { $0.contains("-->") } ?? 0
        let timingParts = lines[timingIndex].components(separatedBy: "-->")
        guard timingParts.count == 2,
              let start = SubtitleTimeParser.parse(timingParts[0]),
              let end = SubtitleTimeParser.parse(timingParts[1]) else { return nil }
        let id = timingIndex > 0 ? lines[0].trimmingCharacters(in: .whitespaces) : UUID().uuidString
        return SubtitleCue(id: id, start: start, end: end, text: cleanText(lines.dropFirst(timingIndex + 1)))
    }

    private func cleanText(_ lines: ArraySlice<String>) -> String {
        lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SubtitleTimeParser {
    static func parse(_ raw: String) -> CMTime? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let parts = trimmed.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else { return nil }
        return CMTime(seconds: hours * 3600 + minutes * 60 + seconds, preferredTimescale: 1000)
    }
}
