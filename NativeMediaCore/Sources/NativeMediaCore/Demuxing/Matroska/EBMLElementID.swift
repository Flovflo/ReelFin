import Foundation

public enum EBMLElementID {
    public static let ebml: UInt32 = 0x1A45DFA3
    public static let segment: UInt32 = 0x18538067
    public static let seekHead: UInt32 = 0x114D9B74
    public static let info: UInt32 = 0x1549A966
    public static let tracks: UInt32 = 0x1654AE6B
    public static let cluster: UInt32 = 0x1F43B675
    public static let cues: UInt32 = 0x1C53BB6B
    public static let timecodeScale: UInt32 = 0x2AD7B1
    public static let duration: UInt32 = 0x4489
    public static let trackEntry: UInt32 = 0xAE
    public static let trackNumber: UInt32 = 0xD7
    public static let trackType: UInt32 = 0x83
    public static let flagDefault: UInt32 = 0x88
    public static let flagForced: UInt32 = 0x55AA
    public static let codecID: UInt32 = 0x86
    public static let codecPrivate: UInt32 = 0x63A2
    public static let language: UInt32 = 0x22B59C
    public static let name: UInt32 = 0x536E
    public static let defaultDuration: UInt32 = 0x23E383
    public static let video: UInt32 = 0xE0
    public static let pixelWidth: UInt32 = 0xB0
    public static let pixelHeight: UInt32 = 0xBA
    public static let colour: UInt32 = 0x55B0
    public static let matrixCoefficients: UInt32 = 0x55B1
    public static let bitsPerChannel: UInt32 = 0x55B2
    public static let chromaSubsamplingHorz: UInt32 = 0x55B3
    public static let chromaSubsamplingVert: UInt32 = 0x55B4
    public static let transferCharacteristics: UInt32 = 0x55BA
    public static let primaries: UInt32 = 0x55BB
    public static let maxCLL: UInt32 = 0x55BC
    public static let maxFALL: UInt32 = 0x55BD
    public static let masteringMetadata: UInt32 = 0x55D0
    public static let masteringLuminanceMax: UInt32 = 0x55D9
    public static let masteringLuminanceMin: UInt32 = 0x55DA
    public static let audio: UInt32 = 0xE1
    public static let samplingFrequency: UInt32 = 0xB5
    public static let channels: UInt32 = 0x9F
    public static let bitDepth: UInt32 = 0x6264
    public static let timecode: UInt32 = 0xE7
    public static let simpleBlock: UInt32 = 0xA3
    public static let blockGroup: UInt32 = 0xA0
    public static let block: UInt32 = 0xA1
    public static let blockDuration: UInt32 = 0x9B
    public static let referenceBlock: UInt32 = 0xFB
    public static let cuePoint: UInt32 = 0xBB
    public static let cueTime: UInt32 = 0xB3
    public static let cueTrackPositions: UInt32 = 0xB7
    public static let cueTrack: UInt32 = 0xF7
    public static let cueClusterPosition: UInt32 = 0xF1
}

public enum EBMLError: LocalizedError, Sendable, Equatable {
    case eof
    case invalidVint(Int)
    case invalidElementSize
    case invalidMatroska(String)

    public var errorDescription: String? {
        switch self {
        case .eof: return "Unexpected end of EBML data."
        case .invalidVint(let offset): return "Invalid EBML variable integer at offset \(offset)."
        case .invalidElementSize: return "Unsupported EBML element size."
        case .invalidMatroska(let reason): return "Invalid Matroska stream: \(reason)"
        }
    }
}
