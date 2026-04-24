import Foundation

enum MPEGTSStreamKind: Sendable, Equatable {
    case video
    case audio
    case unknown
}

struct MPEGTSStream: Sendable, Equatable {
    var pid: Int
    var trackID: Int
    var streamType: UInt8
    var kind: MPEGTSStreamKind
    var codec: String
    var codecPrivateData: Data?
    var audioSampleRate: Double?
    var audioChannels: Int?
}

struct MPEGTSPacket: Sendable, Equatable {
    var pid: Int
    var payloadUnitStart: Bool
    var continuityCounter: UInt8
    var payload: Data
}

struct MPEGTSProgramMap: Sendable, Equatable {
    var pmtPID: Int?
    var streams: [MPEGTSStream]
}

enum MPEGTransportStreamError: LocalizedError, Sendable, Equatable {
    case invalidPacketSize(Int)
    case syncByteMissing(offset: Int64)
    case noProgramMap
    case noElementaryStreams
    case malformedPES(String)

    var errorDescription: String? {
        switch self {
        case .invalidPacketSize(let size):
            return "MPEG-TS packet size \(size) is invalid."
        case .syncByteMissing(let offset):
            return "MPEG-TS sync byte missing at byte \(offset)."
        case .noProgramMap:
            return "MPEG-TS PAT/PMT program map was not found in the original byte stream."
        case .noElementaryStreams:
            return "MPEG-TS PMT did not expose playable elementary streams."
        case .malformedPES(let reason):
            return "MPEG-TS PES packet is malformed: \(reason)."
        }
    }
}
