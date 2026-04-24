import CoreMedia
import Foundation

public struct ASSParser: SubtitleParser {
    public struct ParsedScript: Sendable {
        public var styles: [String: SubtitleStyle]
        public var events: [SubtitleCue]
        public var unsupportedFeatures: [String]
    }

    public init() {}

    public func parse(_ data: Data) throws -> [SubtitleCue] {
        try parseScript(data).events
    }

    public func parseScript(_ data: Data) throws -> ParsedScript {
        let lines = String(decoding: data, as: UTF8.self).components(separatedBy: .newlines)
        var section = ""
        var styleFormat: [String] = []
        var eventFormat: [String] = []
        var styles: [String: SubtitleStyle] = [:]
        var events: [SubtitleCue] = []
        var unsupported = Set<String>()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { section = trimmed.lowercased(); continue }
            if section.contains("styles") {
                parseStyleLine(trimmed, format: &styleFormat, styles: &styles)
            } else if section.contains("events") {
                parseEventLine(trimmed, format: &eventFormat, styles: styles, events: &events, unsupported: &unsupported)
            }
        }
        return ParsedScript(styles: styles, events: events, unsupportedFeatures: unsupported.sorted())
    }

    private func parseStyleLine(_ line: String, format: inout [String], styles: inout [String: SubtitleStyle]) {
        if line.lowercased().hasPrefix("format:") {
            format = fields(afterPrefix: "Format:", line: line).map { $0.lowercased() }
        } else if line.lowercased().hasPrefix("style:") {
            let values = fields(afterPrefix: "Style:", line: line)
            guard let nameIndex = format.firstIndex(of: "name"), values.indices.contains(nameIndex) else { return }
            let size = value("fontsize", in: values, format: format).flatMap(Double.init)
            styles[values[nameIndex]] = SubtitleStyle(
                name: values[nameIndex],
                fontName: value("fontname", in: values, format: format),
                fontSize: size,
                primaryColor: value("primarycolour", in: values, format: format),
                bold: value("bold", in: values, format: format) == "-1",
                italic: value("italic", in: values, format: format) == "-1"
            )
        }
    }

    private func parseEventLine(
        _ line: String,
        format: inout [String],
        styles: [String: SubtitleStyle],
        events: inout [SubtitleCue],
        unsupported: inout Set<String>
    ) {
        if line.lowercased().hasPrefix("format:") {
            format = fields(afterPrefix: "Format:", line: line).map { $0.lowercased() }
        } else if line.lowercased().hasPrefix("dialogue:") {
            let values = fields(afterPrefix: "Dialogue:", line: line, maxSplits: max(format.count - 1, 0))
            guard let startRaw = value("start", in: values, format: format),
                  let endRaw = value("end", in: values, format: format),
                  let start = SubtitleTimeParser.parse(startRaw),
                  let end = SubtitleTimeParser.parse(endRaw) else { return }
            let rawText = value("text", in: values, format: format) ?? ""
            if rawText.contains("\\move") || rawText.contains("\\t(") { unsupported.insert("animated_overrides") }
            let styleName = value("style", in: values, format: format)
            events.append(SubtitleCue(id: "\(events.count + 1)", start: start, end: end, text: clean(rawText), style: styleName.flatMap { styles[$0] }))
        }
    }

    private func fields(afterPrefix prefix: String, line: String, maxSplits: Int = Int.max) -> [String] {
        let body = line.dropFirst(prefix.count)
        return body.split(separator: ",", maxSplits: maxSplits, omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    private func value(_ name: String, in values: [String], format: [String]) -> String? {
        guard let index = format.firstIndex(of: name), values.indices.contains(index) else { return nil }
        return values[index]
    }

    private func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
    }
}
