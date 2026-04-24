import Foundation

public struct AnnexBNALUnit: Equatable, Sendable {
    public var data: Data

    public init(data: Data) {
        self.data = data
    }

    public var h264Type: UInt8? {
        data.first.map { $0 & 0x1F }
    }

    public var hevcType: UInt8? {
        guard let first = data.first else { return nil }
        return (first >> 1) & 0x3F
    }
}

public enum AnnexBNALUnitParser {
    public static func units(in data: Data) -> [AnnexBNALUnit] {
        var units: [AnnexBNALUnit] = []
        var cursor = data.startIndex
        var currentStart: Data.Index?

        while cursor < data.endIndex {
            if let length = startCodeLength(in: data, at: cursor) {
                appendUnit(from: currentStart, to: cursor, in: data, units: &units)
                currentStart = data.index(cursor, offsetBy: length)
                cursor = currentStart ?? data.endIndex
            } else {
                cursor = data.index(after: cursor)
            }
        }
        appendUnit(from: currentStart, to: data.endIndex, in: data, units: &units)
        return units
    }

    public static func makeAVCC(fromAnnexB data: Data, nalUnitLengthSize: Int = 4) -> Data? {
        let units = units(in: data)
        guard
            let sps = units.first(where: { $0.h264Type == 7 })?.data,
            let pps = units.first(where: { $0.h264Type == 8 })?.data,
            sps.count >= 4,
            (1...4).contains(nalUnitLengthSize)
        else { return nil }

        var avcc = Data([1, sps[1], sps[2], sps[3], UInt8(0xFC | (nalUnitLengthSize - 1)), 0xE1])
        appendUInt16(sps.count, to: &avcc)
        avcc.append(sps)
        avcc.append(1)
        appendUInt16(pps.count, to: &avcc)
        avcc.append(pps)
        return avcc
    }

    public static func makeHVCC(fromAnnexB data: Data, nalUnitLengthSize: Int = 4) -> Data? {
        let units = units(in: data)
        let vps = units.filter { $0.hevcType == 32 }.map(\.data)
        let sps = units.filter { $0.hevcType == 33 }.map(\.data)
        let pps = units.filter { $0.hevcType == 34 }.map(\.data)
        guard !vps.isEmpty, !sps.isEmpty, !pps.isEmpty, (1...4).contains(nalUnitLengthSize) else {
            return nil
        }

        var hvcc = Data(repeating: 0, count: 23)
        hvcc[0] = 1
        hvcc[21] = UInt8(0xFC | (nalUnitLengthSize - 1))
        hvcc[22] = 3
        appendHEVCArray(type: 32, units: vps, to: &hvcc)
        appendHEVCArray(type: 33, units: sps, to: &hvcc)
        appendHEVCArray(type: 34, units: pps, to: &hvcc)
        return hvcc
    }

    public static func isH264Keyframe(_ data: Data) -> Bool {
        units(in: data).contains { $0.h264Type == 5 }
    }

    private static func appendUnit(
        from start: Data.Index?,
        to end: Data.Index,
        in data: Data,
        units: inout [AnnexBNALUnit]
    ) {
        guard let start, start < end else { return }
        let unit = trimTrailingZeros(Data(data[start..<end]))
        guard !unit.isEmpty else { return }
        units.append(AnnexBNALUnit(data: unit))
    }

    private static func startCodeLength(in data: Data, at index: Data.Index) -> Int? {
        let remaining = data.distance(from: index, to: data.endIndex)
        guard remaining >= 3 else { return nil }
        if data[index] == 0,
           data[data.index(index, offsetBy: 1)] == 0,
           data[data.index(index, offsetBy: 2)] == 1 {
            return 3
        }
        guard remaining >= 4 else { return nil }
        if data[index] == 0,
           data[data.index(index, offsetBy: 1)] == 0,
           data[data.index(index, offsetBy: 2)] == 0,
           data[data.index(index, offsetBy: 3)] == 1 {
            return 4
        }
        return nil
    }

    private static func trimTrailingZeros(_ data: Data) -> Data {
        var end = data.endIndex
        while end > data.startIndex {
            let previous = data.index(before: end)
            guard data[previous] == 0 else { break }
            end = previous
        }
        return Data(data[data.startIndex..<end])
    }

    private static func appendUInt16(_ value: Int, to data: inout Data) {
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private static func appendHEVCArray(type: UInt8, units: [Data], to data: inout Data) {
        data.append(0x80 | (type & 0x3F))
        appendUInt16(units.count, to: &data)
        for unit in units {
            appendUInt16(unit.count, to: &data)
            data.append(unit)
        }
    }
}
