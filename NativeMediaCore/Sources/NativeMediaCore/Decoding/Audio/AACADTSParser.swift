import Foundation

public struct AACADTSHeader: Equatable, Sendable {
    public var audioObjectType: Int
    public var sampleRate: Double
    public var channels: Int
    public var frameLength: Int
    public var headerLength: Int

    public var audioSpecificConfig: Data {
        Data([
            UInt8((audioObjectType << 3) | ((sampleRateIndex & 0x0E) >> 1)),
            UInt8(((sampleRateIndex & 0x01) << 7) | ((channels & 0x0F) << 3))
        ])
    }

    private var sampleRateIndex: Int {
        Self.sampleRates.firstIndex(of: Int(sampleRate.rounded())) ?? 4
    }

    public static func parse(_ data: Data) -> AACADTSHeader? {
        guard data.count >= 7 else { return nil }
        let b = [UInt8](data.prefix(7))
        guard b[0] == 0xFF, (b[1] & 0xF0) == 0xF0 else { return nil }
        let protectionAbsent = (b[1] & 0x01) == 1
        let profile = Int((b[2] & 0xC0) >> 6)
        let sampleRateIndex = Int((b[2] & 0x3C) >> 2)
        guard let sampleRate = sampleRates[safe: sampleRateIndex] else { return nil }
        let channels = Int((b[2] & 0x01) << 2) | Int((b[3] & 0xC0) >> 6)
        let frameLength = (Int(b[3] & 0x03) << 11) | (Int(b[4]) << 3) | Int((b[5] & 0xE0) >> 5)
        let headerLength = protectionAbsent ? 7 : 9
        guard frameLength >= headerLength else { return nil }
        return AACADTSHeader(
            audioObjectType: profile + 1,
            sampleRate: Double(sampleRate),
            channels: channels,
            frameLength: frameLength,
            headerLength: headerLength
        )
    }

    private static let sampleRates = [
        96_000, 88_200, 64_000, 48_000, 44_100, 32_000, 24_000,
        22_050, 16_000, 12_000, 11_025, 8_000, 7_350
    ]
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
