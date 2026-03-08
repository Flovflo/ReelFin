import Foundation

struct BMFFBox: Equatable {
    let type: String
    let startOffset: Int
    let size: Int
    let children: [BMFFBox]
}

enum BMFFSanityParserError: Error, Equatable {
    case truncatedHeader(offset: Int)
    case invalidSize(offset: Int)
    case sizeOverrun(offset: Int, size: Int)
}

enum BMFFSanityParser {
    private static let containerTypes: Set<String> = [
        "moov", "trak", "mdia", "minf", "stbl", "stsd", "moof", "traf", "mvex", "dinf"
    ]

    static func parseTopLevel(_ data: Data) throws -> [BMFFBox] {
        try parseBoxes(data, range: 0..<data.count)
    }

    static func containsPath(_ path: [String], in boxes: [BMFFBox]) -> Bool {
        guard let first = path.first else { return true }
        for box in boxes where box.type == first {
            if path.count == 1 {
                return true
            }
            if containsPath(Array(path.dropFirst()), in: box.children) {
                return true
            }
        }
        return false
    }

    private static func parseBoxes(_ data: Data, range: Range<Int>) throws -> [BMFFBox] {
        var boxes: [BMFFBox] = []
        var cursor = range.lowerBound

        while cursor < range.upperBound {
            guard cursor + 8 <= range.upperBound else {
                throw BMFFSanityParserError.truncatedHeader(offset: cursor)
            }

            let size32 = readUInt32(data, at: cursor)
            let type = readType(data, at: cursor + 4)

            var size = Int(size32)
            var headerSize = 8
            if size == 1 {
                guard cursor + 16 <= range.upperBound else {
                    throw BMFFSanityParserError.truncatedHeader(offset: cursor)
                }
                let size64 = readUInt64(data, at: cursor + 8)
                size = Int(size64)
                headerSize = 16
            } else if size == 0 {
                size = range.upperBound - cursor
            }

            guard size >= headerSize else {
                throw BMFFSanityParserError.invalidSize(offset: cursor)
            }
            guard cursor + size <= range.upperBound else {
                throw BMFFSanityParserError.sizeOverrun(offset: cursor, size: size)
            }

            let payloadRange = (cursor + headerSize)..<(cursor + size)
            let children: [BMFFBox]
            if containerTypes.contains(type) {
                children = try parseBoxes(data, range: payloadRange)
            } else {
                children = []
            }
            boxes.append(BMFFBox(type: type, startOffset: cursor, size: size, children: children))
            cursor += size
        }

        return boxes
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset]) << 24
        let b1 = UInt32(data[offset + 1]) << 16
        let b2 = UInt32(data[offset + 2]) << 8
        let b3 = UInt32(data[offset + 3])
        return b0 | b1 | b2 | b3
    }

    private static func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for idx in 0..<8 {
            value = (value << 8) | UInt64(data[offset + idx])
        }
        return value
    }

    private static func readType(_ data: Data, at offset: Int) -> String {
        let bytes = [data[offset], data[offset + 1], data[offset + 2], data[offset + 3]]
        return String(decoding: bytes, as: UTF8.self)
    }
}
