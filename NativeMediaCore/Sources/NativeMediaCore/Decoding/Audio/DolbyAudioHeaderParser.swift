import Foundation

public struct DolbyAudioFrameInfo: Equatable, Sendable {
    public var sampleRate: Double
    public var channels: Int
    public var sampleCount: Int
    public var frameSize: Int?
}

public enum DolbyAudioHeaderParser {
    public static func parse(_ data: Data, codec: String) -> DolbyAudioFrameInfo? {
        guard data.count >= 7, data[data.startIndex] == 0x0B, data[data.index(after: data.startIndex)] == 0x77 else {
            return nil
        }
        switch codec.lowercased() {
        case "eac3":
            return parseEAC3(data)
        default:
            return parseAC3(data)
        }
    }

    private static func parseEAC3(_ data: Data) -> DolbyAudioFrameInfo? {
        guard data.count >= 5 else { return nil }
        let frameSizeCode = (Int(data[2] & 0x07) << 8) | Int(data[3])
        let fscod = Int((data[4] & 0xC0) >> 6)
        let numblkscod = Int((data[4] & 0x30) >> 4)
        let sampleRate: Int?
        if fscod == 3 {
            sampleRate = halfSampleRates[safe: numblkscod]
        } else {
            sampleRate = sampleRates[safe: fscod]
        }
        guard let sampleRate else { return nil }
        let acmod = Int((data[4] & 0x0E) >> 1)
        let lfeon = Int(data[4] & 0x01)
        let blocks = fscod == 3 ? 6 : ([1, 2, 3, 6][safe: numblkscod] ?? 6)
        return DolbyAudioFrameInfo(
            sampleRate: Double(sampleRate),
            channels: channelCount(acmod: acmod, lfeon: lfeon),
            sampleCount: blocks * 256,
            frameSize: (frameSizeCode + 1) * 2
        )
    }

    private static func parseAC3(_ data: Data) -> DolbyAudioFrameInfo? {
        var bits = BitReader(data: data)
        guard bits.read(16) == 0x0B77 else { return nil }
        _ = bits.read(16)
        let fscod = bits.read(2)
        guard let sampleRate = sampleRates[safe: fscod] else { return nil }
        let frameSizeCode = bits.read(6)
        _ = bits.read(5)
        _ = bits.read(3)
        let acmod = bits.read(3)
        if (acmod & 0x01) != 0, acmod != 0x01 { _ = bits.read(2) }
        if (acmod & 0x04) != 0 { _ = bits.read(2) }
        if acmod == 0x02 { _ = bits.read(2) }
        let lfeon = bits.read(1)
        return DolbyAudioFrameInfo(
            sampleRate: Double(sampleRate),
            channels: channelCount(acmod: acmod, lfeon: lfeon),
            sampleCount: 1536,
            frameSize: ac3FrameSizeBytes(fscod: fscod, frameSizeCode: frameSizeCode)
        )
    }

    private static func channelCount(acmod: Int, lfeon: Int) -> Int {
        (channelTable[safe: acmod] ?? 2) + lfeon
    }

    private static func ac3FrameSizeBytes(fscod: Int, frameSizeCode: Int) -> Int? {
        let index = frameSizeCode / 2
        guard let wordsByRate = ac3FrameSizeWords[safe: index],
              let words = wordsByRate[safe: fscod] else {
            return nil
        }
        return words * 2
    }

    private static let sampleRates = [48_000, 44_100, 32_000]
    private static let halfSampleRates = [24_000, 22_050, 16_000]
    private static let channelTable = [2, 1, 2, 3, 3, 4, 4, 5]
    private static let ac3FrameSizeWords = [
        [64, 69, 96], [80, 87, 120], [96, 104, 144], [112, 121, 168],
        [128, 139, 192], [160, 174, 240], [192, 208, 288], [224, 243, 336],
        [256, 278, 384], [320, 348, 480], [384, 417, 576], [448, 487, 672],
        [512, 557, 768], [640, 696, 960], [768, 835, 1152], [896, 975, 1344],
        [1024, 1114, 1536], [1152, 1253, 1728], [1280, 1393, 1920]
    ]
}

private struct BitReader {
    private let bytes: [UInt8]
    private var bitOffset = 0

    init(data: Data) {
        self.bytes = Array(data)
    }

    mutating func read(_ count: Int) -> Int {
        var value = 0
        for _ in 0..<count {
            let byteIndex = bitOffset / 8
            guard byteIndex < bytes.count else { return value }
            let shift = 7 - (bitOffset % 8)
            value = (value << 1) | Int((bytes[byteIndex] >> shift) & 1)
            bitOffset += 1
        }
        return value
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
