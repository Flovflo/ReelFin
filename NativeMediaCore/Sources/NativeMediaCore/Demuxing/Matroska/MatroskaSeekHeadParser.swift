import Foundation

public struct MatroskaSeekHeadParser: Sendable {
    private let reader = EBMLReader()

    public init() {}

    public func parse(data: Data) -> [UInt32: UInt64] {
        var entries: [UInt32: UInt64] = [:]
        var offset = 0
        while offset < data.count {
            guard let header = try? reader.readHeader(data: data, offset: offset),
                  let size = header.size,
                  size >= 0,
                  let sizeInt = Int(exactly: size) else {
                break
            }
            let end = header.payloadOffset + sizeInt
            guard end <= data.count else { break }
            if header.id == EBMLElementID.seek,
               let entry = parseSeekEntry(data: data, header: header) {
                entries[entry.id] = entry.position
            }
            guard end > offset else { break }
            offset = end
        }
        return entries
    }

    private func parseSeekEntry(data: Data, header: EBMLElementHeader) -> (id: UInt32, position: UInt64)? {
        var seekID: UInt32?
        var seekPosition: UInt64?
        var offset = header.payloadOffset
        let end = payloadEnd(header)
        while offset < end {
            guard let child = try? reader.readHeader(data: data, offset: offset),
                  let size = child.size,
                  size >= 0,
                  let sizeInt = Int(exactly: size) else {
                return nil
            }
            let childEnd = child.payloadOffset + sizeInt
            guard childEnd <= data.count, childEnd <= end else { return nil }
            if child.id == EBMLElementID.seekID {
                seekID = readElementIDPayload(data: data, offset: child.payloadOffset, size: sizeInt)
            } else if child.id == EBMLElementID.seekPosition {
                seekPosition = try? reader.readUInt(data: data, offset: child.payloadOffset, size: sizeInt)
            }
            guard childEnd > offset else { return nil }
            offset = childEnd
        }
        guard let seekID, let seekPosition else { return nil }
        return (seekID, seekPosition)
    }

    private func readElementIDPayload(data: Data, offset: Int, size: Int) -> UInt32? {
        guard size > 0, size <= 4, offset + size <= data.count else { return nil }
        return data[offset..<offset + size].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private func payloadEnd(_ header: EBMLElementHeader) -> Int {
        header.payloadOffset + Int(header.size ?? 0)
    }
}
