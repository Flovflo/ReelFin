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

    public func readHeader(data: Data, offset: Int) throws -> EBMLElementHeader {
        let id = try readElementID(data: data, offset: offset)
        let size = try readElementSize(data: data, offset: offset + id.length)
        return EBMLElementHeader(
            id: id.value,
            idLength: id.length,
            size: size.value,
            sizeLength: size.length,
            payloadOffset: offset + id.length + size.length
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
        guard length <= 4, offset + length <= data.count else { throw EBMLError.invalidVint(offset) }
        var value: UInt32 = 0
        for byte in data[offset..<offset + length] {
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
        guard length <= 8, offset + length <= data.count else { throw EBMLError.invalidVint(offset) }
        var value = UInt64(first & ~mask)
        for byte in data[offset + 1..<offset + length] {
            value = (value << 8) | UInt64(byte)
        }
        let unknown = (UInt64(1) << UInt64(7 * length)) - 1
        return (value == unknown ? nil : Int64(value), length)
    }

    public func readUInt(data: Data, offset: Int, size: Int) throws -> UInt64 {
        guard size >= 0, size <= 8, offset + size <= data.count else { throw EBMLError.eof }
        return data[offset..<offset + size].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    public func readFloat(data: Data, offset: Int, size: Int) throws -> Double {
        guard offset + size <= data.count else { throw EBMLError.eof }
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
        guard offset + size <= data.count else { throw EBMLError.eof }
        let payload = data[offset..<offset + size].split(separator: 0).first ?? []
        return String(data: Data(payload), encoding: .utf8) ?? String(data: Data(payload), encoding: .isoLatin1) ?? ""
    }
}

extension Data {
    subscript(safe index: Int) -> UInt8? {
        indices.contains(index) ? self[index] : nil
    }
}
