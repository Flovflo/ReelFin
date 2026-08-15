import Foundation

public struct MatroskaSeekHeadParser: Sendable {
    private let reader = EBMLReader()

    public init() {}

    public func parse(data: Data) throws -> [UInt32: UInt64] {
        var entries: [UInt32: UInt64] = [:]
        var offset = 0
        while offset < data.count {
            let header = try reader.readHeader(data: data, offset: offset)
            let range = try reader.payloadRange(
                for: header,
                elementOffset: offset,
                parentEnd: data.count,
                dataCount: data.count
            )
            if header.id == EBMLElementID.seek {
                let entry = try parseSeekEntry(data: data, payloadRange: range)
                entries[entry.id] = entry.position
            }
            offset = range.upperBound
        }
        return entries
    }

    private func parseSeekEntry(data: Data, payloadRange: Range<Int>) throws -> (id: UInt32, position: UInt64) {
        var seekID: UInt32?
        var seekPosition: UInt64?
        var offset = payloadRange.lowerBound
        while offset < payloadRange.upperBound {
            let child = try reader.readHeader(data: data, offset: offset)
            let childRange = try reader.payloadRange(
                for: child,
                elementOffset: offset,
                parentEnd: payloadRange.upperBound,
                dataCount: data.count
            )
            if child.id == EBMLElementID.seekID {
                seekID = try readElementIDPayload(data: data, range: childRange)
            } else if child.id == EBMLElementID.seekPosition {
                seekPosition = try reader.readUInt(
                    data: data,
                    offset: childRange.lowerBound,
                    size: childRange.count
                )
            }
            offset = childRange.upperBound
        }
        guard let seekID, let seekPosition else {
            throw EBMLError.invalidMatroska("Seek entry is missing SeekID or SeekPosition")
        }
        return (seekID, seekPosition)
    }

    private func readElementIDPayload(data: Data, range: Range<Int>) throws -> UInt32 {
        guard !range.isEmpty, range.count <= 4 else {
            throw EBMLError.invalidElementSize
        }
        return data[range].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}
