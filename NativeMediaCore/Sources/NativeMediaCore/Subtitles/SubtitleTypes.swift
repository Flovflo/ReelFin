import CoreGraphics
import CoreMedia
import Foundation

public enum SubtitleFormat: String, Codable, Hashable, Sendable {
    case srt
    case webVTT
    case ass
    case ssa
    case pgs
    case vobSub
    case matroskaText
    case unknown
}

public struct SubtitleStyle: Codable, Hashable, Sendable {
    public var name: String
    public var fontName: String?
    public var fontSize: Double?
    public var primaryColor: String?
    public var bold: Bool
    public var italic: Bool

    public init(
        name: String = "Default",
        fontName: String? = nil,
        fontSize: Double? = nil,
        primaryColor: String? = nil,
        bold: Bool = false,
        italic: Bool = false
    ) {
        self.name = name
        self.fontName = fontName
        self.fontSize = fontSize
        self.primaryColor = primaryColor
        self.bold = bold
        self.italic = italic
    }
}

public struct SubtitleCue: Identifiable, Hashable, Sendable {
    public var id: String
    public var start: CMTime
    public var end: CMTime
    public var text: String
    public var style: SubtitleStyle?
    public var position: CGPoint?

    public init(id: String, start: CMTime, end: CMTime, text: String, style: SubtitleStyle? = nil, position: CGPoint? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.style = style
        self.position = position
    }
}

public protocol SubtitleParser: Sendable {
    func parse(_ data: Data) throws -> [SubtitleCue]
}

public protocol SubtitleRenderer: Sendable {
    func render(cues: [SubtitleCue], at time: CMTime) async
}

public struct PGSSubtitlePacket: Hashable, Sendable {
    public var presentationTimestamp: CMTime
    public var segmentType: UInt8
    public var payload: Data

    public init(presentationTimestamp: CMTime, segmentType: UInt8, payload: Data) {
        self.presentationTimestamp = presentationTimestamp
        self.segmentType = segmentType
        self.payload = payload
    }
}

public struct VobSubPacket: Hashable, Sendable {
    public var presentationTimestamp: CMTime
    public var payload: Data

    public init(presentationTimestamp: CMTime, payload: Data) {
        self.presentationTimestamp = presentationTimestamp
        self.payload = payload
    }
}
