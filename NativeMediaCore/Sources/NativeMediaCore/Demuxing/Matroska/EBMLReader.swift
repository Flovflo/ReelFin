import Foundation

public struct EBMLElementHeader: Sendable, Equatable {
    public var id: UInt32
    public var idLength: Int
    public var size: Int64?
    public var sizeLength: Int
    public var payloadOffset: Int
    public var totalHeaderSize: Int { idLength + sizeLength }
}

public struct EBMLReader: Sendable {
    public init() {}

    public func checkedRange(
        offset: Int,
        size: Int,
        parentEnd: Int,
        dataCount: Int
    ) throws -> Range<Int> {
        guard offset >= 0, size >= 0, parentEnd >= 0, dataCount >= 0 else {
            throw EBMLError.invalidElementSize
        }
        let (end, overflow) = offset.addingReportingOverflow(size)
        guard !overflow,
              offset <= parentEnd,
              offset <= dataCount,
              end <= parentEnd,
              end <= dataCount else {
            throw EBMLError.invalidElementSize
        }
        return offset..<end
    }

    public func payloadRange(
        for header: EBMLElementHeader,
        elementOffset: Int,
        parentEnd: Int,
        dataCount: Int,
        unknownSizeEnd: Int? = nil
    ) throws -> Range<Int> {
        let payloadSize: Int
        if let size = header.size {
            guard size >= 0, let exactSize = Int(exactly: size) else {
                throw EBMLError.invalidElementSize
            }
            payloadSize = exactSize
        } else {
            guard let unknownSizeEnd, unknownSizeEnd >= header.payloadOffset else {
                throw EBMLError.invalidElementSize
            }
            payloadSize = unknownSizeEnd - header.payloadOffset
        }
        let range = try checkedRange(
            offset: header.payloadOffset,
            size: payloadSize,
            parentEnd: parentEnd,
            dataCount: dataCount
        )
        guard header.payloadOffset > elementOffset, range.upperBound > elementOffset else {
            throw EBMLError.invalidElementSize
        }
        return range
    }

    public func exactInt(_ value: UInt64) throws -> Int {
        guard let result = Int(exactly: value) else {
            throw EBMLError.invalidElementSize
        }
        return result
    }

    public func exactInt64(_ value: UInt64) throws -> Int64 {
        guard let result = Int64(exactly: value) else {
            throw EBMLError.invalidElementSize
        }
        return result
    }

    public func finiteFloat(_ value: Double) throws -> Double {
        guard value.isFinite else {
            throw EBMLError.invalidElementSize
        }
        return value
    }

    public func checkedAdd(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw EBMLError.invalidElementSize }
        return result
    }

    public func checkedMultiply(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow else { throw EBMLError.invalidElementSize }
        return result
    }

    public func readHeader(data: Data, offset: Int) throws -> EBMLElementHeader {
        let id = try readElementID(data: data, offset: offset)
        let sizeOffset = try checkedRange(
            offset: offset,
            size: id.length,
            parentEnd: data.count,
            dataCount: data.count
        ).upperBound
        let size = try readElementSize(data: data, offset: sizeOffset)
        let payloadOffset = try checkedRange(
            offset: sizeOffset,
            size: size.length,
            parentEnd: data.count,
            dataCount: data.count
        ).upperBound
        return EBMLElementHeader(
            id: id.value,
            idLength: id.length,
            size: size.value,
            sizeLength: size.length,
            payloadOffset: payloadOffset
        )
    }

    public func readElementID(data: Data, offset: Int) throws -> (value: UInt32, length: Int) {
        guard let first = data[safe: offset] else { throw EBMLError.eof }
        var mask: UInt8 = 0x80
        var length = 1
        while length <= 4, (first & mask) == 0 {
            mask >>= 1
            length += 1
        }
        guard length <= 4,
              let range = try? checkedRange(
                offset: offset,
                size: length,
                parentEnd: data.count,
                dataCount: data.count
              ) else {
            throw EBMLError.invalidVint(offset)
        }
        var value: UInt32 = 0
        for byte in data[range] {
            value = (value << 8) | UInt32(byte)
        }
        return (value, length)
    }

    public func readElementSize(data: Data, offset: Int) throws -> (value: Int64?, length: Int) {
        guard let first = data[safe: offset] else { throw EBMLError.eof }
        var mask: UInt8 = 0x80
        var length = 1
        while length <= 8, (first & mask) == 0 {
            mask >>= 1
            length += 1
        }
        guard length <= 8,
              let range = try? checkedRange(
                offset: offset,
                size: length,
                parentEnd: data.count,
                dataCount: data.count
              ) else {
            throw EBMLError.invalidVint(offset)
        }
        var value = UInt64(first & ~mask)
        for byte in data[range.dropFirst()] {
            value = (value << 8) | UInt64(byte)
        }
        let unknown = (UInt64(1) << UInt64(7 * length)) - 1
        return (value == unknown ? nil : Int64(value), length)
    }

    public func readUInt(data: Data, offset: Int, size: Int) throws -> UInt64 {
        guard size <= 8,
              let range = try? checkedRange(
                offset: offset,
                size: size,
                parentEnd: data.count,
                dataCount: data.count
              ) else {
            throw EBMLError.eof
        }
        return data[range].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    public func readFloat(data: Data, offset: Int, size: Int) throws -> Double {
        guard (try? checkedRange(
            offset: offset,
            size: size,
            parentEnd: data.count,
            dataCount: data.count
        )) != nil else {
            throw EBMLError.eof
        }
        if size == 4 {
            let bits = UInt32(try readUInt(data: data, offset: offset, size: size))
            return Double(Float(bitPattern: bits))
        }
        if size == 8 {
            return Double(bitPattern: try readUInt(data: data, offset: offset, size: size))
        }
        throw EBMLError.invalidElementSize
    }

    public func readString(data: Data, offset: Int, size: Int) throws -> String {
        let range: Range<Int>
        do {
            range = try checkedRange(
                offset: offset,
                size: size,
                parentEnd: data.count,
                dataCount: data.count
            )
        } catch {
            throw EBMLError.eof
        }
        let payload = data[range].split(separator: 0).first ?? []
        return String(data: Data(payload), encoding: .utf8) ?? String(data: Data(payload), encoding: .isoLatin1) ?? ""
    }
}

extension Data {
    subscript(safe index: Int) -> UInt8? {
        indices.contains(index) ? self[index] : nil
    }
}
