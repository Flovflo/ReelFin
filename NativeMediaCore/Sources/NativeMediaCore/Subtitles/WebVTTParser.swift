import Foundation

public struct WebVTTParser: SubtitleParser {
    public init() {}

    public func parse(_ data: Data) throws -> [SubtitleCue] {
        let text = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return text.components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("WEBVTT") }
            .compactMap(parseBlock)
    }

    private func parseBlock(_ block: String) -> SubtitleCue? {
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
        let timing = lines[timingIndex].components(separatedBy: "-->")
        guard timing.count == 2,
              let start = SubtitleTimeParser.parse(timing[0]),
              let end = SubtitleTimeParser.parse(timing[1].split(separator: " ").first.map(String.init) ?? timing[1]) else { return nil }
        let id = timingIndex > 0 ? lines[0] : UUID().uuidString
        return SubtitleCue(
            id: id,
            start: start,
            end: end,
            text: lines.dropFirst(timingIndex + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
