import Foundation

public struct AVCDecoderConfiguration: Sendable, Equatable {
    public var nalUnitLengthSize: Int
    public var sps: [Data]
    public var pps: [Data]
}

public struct HEVCDecoderConfiguration: Sendable, Equatable {
    public var nalUnitLengthSize: Int
    public var vps: [Data]
    public var sps: [Data]
    public var pps: [Data]

    public init(nalUnitLengthSize: Int, vps: [Data], sps: [Data], pps: [Data]) {
        self.nalUnitLengthSize = nalUnitLengthSize
        self.vps = vps
        self.sps = sps
        self.pps = pps
    }
}

public enum VideoCodecPrivateDataParser {
    public static func parseAVCDecoderConfigurationRecord(_ data: Data) throws -> AVCDecoderConfiguration {
        guard data.count >= 7 else {
            throw FallbackReason.videoToolboxFormatDescriptionFailed(codecPrivateReason: "avcC too short")
        }
        let lengthSize = Int(data[4] & 0x03) + 1
        let spsCount = Int(data[5] & 0x1F)
        var offset = 6
        var sps: [Data] = []
        for _ in 0..<spsCount {
            let length = try readLength(data, offset: &offset)
            guard offset + length <= data.count else { throw malformed("SPS extends past avcC") }
            sps.append(Data(data[offset..<offset + length]))
            offset += length
        }
        guard offset < data.count else { throw malformed("missing PPS count") }
        let ppsCount = Int(data[offset])
        offset += 1
        var pps: [Data] = []
        for _ in 0..<ppsCount {
            let length = try readLength(data, offset: &offset)
            guard offset + length <= data.count else { throw malformed("PPS extends past avcC") }
            pps.append(Data(data[offset..<offset + length]))
            offset += length
        }
        return AVCDecoderConfiguration(nalUnitLengthSize: lengthSize, sps: sps, pps: pps)
    }

    public static func parseHEVCDecoderConfigurationRecord(_ data: Data) throws -> HEVCDecoderConfiguration {
        guard data.count >= 23 else {
            throw FallbackReason.videoToolboxFormatDescriptionFailed(codecPrivateReason: "hvcC too short")
        }
        let lengthSize = Int(data[21] & 0x03) + 1
        let arrayCount = Int(data[22])
        var offset = 23
        var vps: [Data] = []
        var sps: [Data] = []
        var pps: [Data] = []
        for _ in 0..<arrayCount {
            guard offset + 3 <= data.count else { throw malformed("truncated hvcC array header") }
            let nalType = data[offset] & 0x3F
            offset += 1
            let nalCount = Int(data[offset]) << 8 | Int(data[offset + 1])
            offset += 2
            for _ in 0..<nalCount {
                let length = try readLength(data, offset: &offset)
                guard offset + length <= data.count else { throw malformed("HEVC NAL extends past hvcC") }
                let nal = Data(data[offset..<offset + length])
                offset += length
                switch nalType {
                case 32: vps.append(nal)
                case 33: sps.append(nal)
                case 34: pps.append(nal)
                default: break
                }
            }
        }
        return HEVCDecoderConfiguration(nalUnitLengthSize: lengthSize, vps: vps, sps: sps, pps: pps)
    }

    private static func readLength(_ data: Data, offset: inout Int) throws -> Int {
        guard offset + 2 <= data.count else { throw malformed("truncated parameter-set length") }
        defer { offset += 2 }
        return Int(data[offset]) << 8 | Int(data[offset + 1])
    }

    private static func malformed(_ reason: String) -> FallbackReason {
        .videoToolboxFormatDescriptionFailed(codecPrivateReason: reason)
    }
}
