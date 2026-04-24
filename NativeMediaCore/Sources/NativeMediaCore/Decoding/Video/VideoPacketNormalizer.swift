import Foundation

public enum VideoPacketNormalizer {
    public static func normalizeLengthPrefixedNALUnits(
        _ data: Data,
        nalUnitLengthSize: Int?
    ) throws -> Data {
        guard isAnnexB(data) else { return data }
        guard let nalUnitLengthSize, [1, 2, 4].contains(nalUnitLengthSize) else {
            throw FallbackReason.videoToolboxFormatDescriptionFailed(
                codecPrivateReason: "Annex B packet requires known NAL length size"
            )
        }
        let units = annexBNALUnits(in: data)
        guard !units.isEmpty else {
            throw FallbackReason.videoToolboxFormatDescriptionFailed(codecPrivateReason: "Annex B packet has no NAL units")
        }
        var converted = Data()
        for unit in units {
            appendLength(unit.count, bytes: nalUnitLengthSize, to: &converted)
            converted.append(unit)
        }
        return converted
    }

    private static func isAnnexB(_ data: Data) -> Bool {
        startCodeLength(in: data, at: data.startIndex) != nil
    }

    private static func annexBNALUnits(in data: Data) -> [Data] {
        var units: [Data] = []
        var cursor = data.startIndex
        var currentStart: Data.Index?

        while cursor < data.endIndex {
            if let length = startCodeLength(in: data, at: cursor) {
                if let start = currentStart, start < cursor {
                    units.append(trimTrailingZeros(Data(data[start..<cursor])))
                }
                currentStart = data.index(cursor, offsetBy: length)
                cursor = currentStart ?? data.endIndex
            } else {
                cursor = data.index(after: cursor)
            }
        }

        if let start = currentStart, start < data.endIndex {
            units.append(trimTrailingZeros(Data(data[start..<data.endIndex])))
        }
        return units.filter { !$0.isEmpty }
    }

    private static func startCodeLength(in data: Data, at index: Data.Index) -> Int? {
        guard index < data.endIndex else { return nil }
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

    private static func appendLength(_ length: Int, bytes: Int, to data: inout Data) {
        for shift in stride(from: (bytes - 1) * 8, through: 0, by: -8) {
            data.append(UInt8((length >> shift) & 0xFF))
        }
    }
}
