import Foundation
import Shared

/// Low-level binary utility to parse Extensible Binary Meta Language (EBML)
/// structures, which form the basis of the Matroska (MKV and WebM) container formats.
public struct EBMLParser {
    
    // MARK: - Constants
    
    // Core EBML IDs
    public static let idEBML: UInt32 = 0x1A45DFA3
    public static let idSegment: UInt32 = 0x18538067
    
    // Segment Sub-Elements
    public static let idInfo: UInt32 = 0x1549A966
    public static let idTracks: UInt32 = 0x1654AE6B
    public static let idCues: UInt32 = 0x1C53BB6B
    public static let idCluster: UInt32 = 0x1F43B675

    // Cues Sub-Elements
    public static let idCuePoint: UInt32 = 0xBB
    public static let idCueTime: UInt32 = 0xB3
    public static let idCueTrackPositions: UInt32 = 0xB7
    public static let idCueTrack: UInt32 = 0xF7
    public static let idCueClusterPosition: UInt32 = 0xF1
    
    // Cluster Sub-Elements
    public static let idTimecode: UInt32 = 0xE7
    public static let idSimpleBlock: UInt32 = 0xA3
    public static let idBlockGroup: UInt32 = 0xA0
    public static let idBlock: UInt32 = 0xA1
    public static let idBlockDuration: UInt32 = 0x9B
    
    // Track Sub-Elements
    public static let idTrackEntry: UInt32 = 0xAE
    public static let idTrackNumber: UInt32 = 0xD7
    public static let idTrackType: UInt32 = 0x83
    public static let idCodecID: UInt32 = 0x86
    public static let idCodecPrivate: UInt32 = 0x63A2
    public static let idDefaultDuration: UInt32 = 0x23E383
    
    // Video Track Sub-Elements
    public static let idVideo: UInt32 = 0xE0
    public static let idPixelWidth: UInt32 = 0xB0
    public static let idPixelHeight: UInt32 = 0xBA
    public static let idColour: UInt32 = 0x55B0
    public static let idMatrixCoefficients: UInt32 = 0x55B1
    public static let idBitsPerChannel: UInt32 = 0x55B2
    public static let idTransferCharacteristics: UInt32 = 0x55BA
    public static let idPrimaries: UInt32 = 0x55BB
    
    // Audio Track Sub-Elements
    public static let idAudio: UInt32 = 0xE1
    public static let idSamplingFrequency: UInt32 = 0xB5
    public static let idChannels: UInt32 = 0x9F
    public static let idBitDepth: UInt32 = 0x6264

    // Track flags and language
    public static let idFlagDefault: UInt32 = 0x88
    public static let idFlagForced: UInt32 = 0x55AA
    public static let idLanguage: UInt32 = 0x22B59C

    // Colour HDR – MaxCLL / MaxFALL / MasteringMetadata
    public static let idMaxCLL: UInt32 = 0x55BC
    public static let idMaxFALL: UInt32 = 0x55BD
    public static let idMasteringMetadata: UInt32 = 0x55D0
    public static let idMasteringLuminanceMax: UInt32 = 0x55D9
    public static let idMasteringLuminanceMin: UInt32 = 0x55DA
    // Primaries (stored as doubles, in 0..1 range)
    public static let idPrimaryRX: UInt32 = 0x55D1
    public static let idPrimaryRY: UInt32 = 0x55D2
    public static let idPrimaryGX: UInt32 = 0x55D3
    public static let idPrimaryGY: UInt32 = 0x55D4
    public static let idPrimaryBX: UInt32 = 0x55D5
    public static let idPrimaryBY: UInt32 = 0x55D6
    public static let idWhitePointX: UInt32 = 0x55D7
    public static let idWhitePointY: UInt32 = 0x55D8

    // BlockGroup sub-elements
    public static let idReferenceBlock: UInt32 = 0xFB

    // Info Sub-Elements
    public static let idTimecodeScale: UInt32 = 0x2AD7B1
    public static let idDuration: UInt32 = 0x4489
    
    // MARK: - Variable-Size Integer (VINT) Parsing
    
    /// Result of parsing a VarInt (Variable-Size Integer).
    public struct VarIntResult: Equatable {
        /// The parsed decoded value (up to 8 bytes).
        public let value: UInt64
        /// The total number of bytes consumed to read this VarInt (header + payload).
        public let length: Int
    }
    
    /// Parses an EBML element ID from the given data, starting at `offset`.
    /// 
    /// In EBML, IDs are encoded exactly like VarInts, but their value includes the 
    /// length marker bits. (e.g., length 4, first byte 0x1A -> ID 0x1A45DFA3).
    /// Returns the raw UInt32 ID and the length of the ID in bytes.
    public static func readElementID(data: Data, offset: Int) throws -> (id: UInt32, length: Int) {
        guard offset >= 0 else {
            throw NativeBridgeError.invalidMKV("Negative EBML ID offset \(offset)")
        }
        guard offset < data.count else { throw NativeBridgeError.demuxerEOF }
        
        let firstByte = byte(at: offset, in: data)
        let length = varIntLength(from: firstByte)
        guard length > 0 else {
            throw NativeBridgeError.invalidMKV("Invalid EBML element ID length marker at offset \(offset)")
        }
        
        _ = try checkedEnd(offset: offset, length: length, dataCount: data.count, context: "element-id")
        guard length <= 4 else {
            // EBML element IDs are structurally defined to be max 4 bytes long (Class A, B, C, D)
            AppLog.playback.error("Invalid EBML Element ID length: \(length)")
            throw NativeBridgeError.demuxerFailed("Invalid EBML Element ID length (> 4).")
        }
        
        var id: UInt32 = 0
        for i in 0..<length {
            id = (id << 8) | UInt32(byte(at: offset + i, in: data))
        }
        
        return (id, length)
    }
    
    /// Parses an EBML Element Size (payload size) from the given data, starting at `offset`.
    /// 
    /// Sizes are typical VarInts, where the length marker bits are masked out.
    /// Returns the payload size and the length of the VarInt header in bytes.
    public static func readElementSize(data: Data, offset: Int) throws -> VarIntResult {
        guard offset >= 0 else {
            throw NativeBridgeError.invalidMKV("Negative EBML size offset \(offset)")
        }
        guard offset < data.count else { throw NativeBridgeError.demuxerEOF }
        
        let firstByte = byte(at: offset, in: data)
        let length = varIntLength(from: firstByte)
        guard length > 0 else {
            throw NativeBridgeError.invalidMKV("Invalid EBML element size marker at offset \(offset)")
        }
        
        _ = try checkedEnd(offset: offset, length: length, dataCount: data.count, context: "element-size")
        guard length <= 8 else {
            AppLog.playback.error("Invalid EBML Element Size length: \(length)")
            throw NativeBridgeError.demuxerFailed("Invalid EBML Size length (> 8).")
        }
        
        // Mask out the size marker bit.
        // E.g., if length is 1, mask is 0x7F. If length is 2, mask is 0x3F.
        let mask = UInt8(0xFF >> length)
        var value: UInt64 = UInt64(firstByte & mask)
        
        for i in 1..<length {
            value = (value << 8) | UInt64(byte(at: offset + i, in: data))
        }
        
        // Define unknown size (all 1s in the data section).
        // Standard Matroska defines 1-byte unknown = 0xFF, 8-byte unknown = 0xFFFFFFFFFFFFFF
        let isUnknownSize: Bool
        switch length {
        case 1: isUnknownSize = (value == 0x7F)
        case 2: isUnknownSize = (value == 0x3FFF)
        case 3: isUnknownSize = (value == 0x1FFFFF)
        case 4: isUnknownSize = (value == 0x0FFFFFFF)
        case 5: isUnknownSize = (value == 0x07FFFFFFFF)
        case 6: isUnknownSize = (value == 0x03FFFFFFFFFF)
        case 7: isUnknownSize = (value == 0x01FFFFFFFFFFFF)
        case 8: isUnknownSize = (value == 0x00FFFFFFFFFFFFFF)
        default: isUnknownSize = false
        }
        
        if isUnknownSize {
            AppLog.playback.debug("EBML Size: Unknown length encountered (len: \(length))")
            // We use UInt64.max as the sentinel for "unknown size"
            return VarIntResult(value: UInt64.max, length: length)
        }
        
        return VarIntResult(value: value, length: length)
    }
    
    // MARK: - Payload Data Extractors
    
    /// Parses an Unsigned Integer (UInt) payload of max 8 bytes.
    public static func readUInt(data: Data, offset: Int, size: Int) throws -> UInt64 {
        guard size > 0, size <= 8 else {
            if size == 0 { return 0 }
            throw NativeBridgeError.demuxerFailed("Invalid UInt size \(size)")
        }
        guard offset >= 0 else {
            throw NativeBridgeError.invalidMKV("Negative UInt offset \(offset)")
        }
        _ = try checkedEnd(offset: offset, length: size, dataCount: data.count, context: "uint")
        
        var value: UInt64 = 0
        for i in 0..<size {
            value = (value << 8) | UInt64(byte(at: offset + i, in: data))
        }
        return value
    }
    
    /// Parses a Signed Integer (Int) payload of max 8 bytes.
    public static func readInt(data: Data, offset: Int, size: Int) throws -> Int64 {
        guard size > 0, size <= 8 else {
            if size == 0 { return 0 }
            throw NativeBridgeError.demuxerFailed("Invalid Int size \(size)")
        }
        guard offset >= 0 else {
            throw NativeBridgeError.invalidMKV("Negative Int offset \(offset)")
        }
        _ = try checkedEnd(offset: offset, length: size, dataCount: data.count, context: "int")
        
        // Two's complement base
        var value: Int64 = Int64(bitPattern: UInt64(byte(at: offset, in: data)))
        if (value & 0x80) != 0 {
            // Sign extend the remaining bits of the Int64
            let shiftCount = 64 - 8
            value = (value << shiftCount) >> shiftCount
        }
        
        for i in 1..<size {
            value = (value << 8) | Int64(byte(at: offset + i, in: data))
        }
        return value
    }
    
    /// Parses a Float payload (4 bytes IEEE-754 Single or 8 bytes IEEE-754 Double).
    public static func readFloat(data: Data, offset: Int, size: Int) throws -> Double {
        guard size >= 0 else {
            throw NativeBridgeError.demuxerFailed("Negative Float size \(size)")
        }
        guard offset >= 0 else {
            throw NativeBridgeError.invalidMKV("Negative Float offset \(offset)")
        }
        _ = try checkedEnd(offset: offset, length: size, dataCount: data.count, context: "float")
        
        if size == 4 {
            var raw: UInt32 = 0
            for i in 0..<4 { raw = (raw << 8) | UInt32(byte(at: offset + i, in: data)) }
            return Double(Float(bitPattern: raw))
        } else if size == 8 {
            var raw: UInt64 = 0
            for i in 0..<8 { raw = (raw << 8) | UInt64(byte(at: offset + i, in: data)) }
            return Double(bitPattern: raw)
        } else if size == 0 {
            return 0.0
        } else {
            throw NativeBridgeError.demuxerFailed("Invalid Float size \(size)")
        }
    }
    
    /// Parses a String (ASCII) payload.
    public static func readString(data: Data, offset: Int, size: Int) throws -> String {
        guard size >= 0 else { throw NativeBridgeError.demuxerFailed("Negative string size") }
        if size == 0 { return "" }
        guard offset >= 0 else {
            throw NativeBridgeError.invalidMKV("Negative String offset \(offset)")
        }
        _ = try checkedEnd(offset: offset, length: size, dataCount: data.count, context: "string")
        
        // Often strings are null-terminated in EBML
        let startIndex = data.index(data.startIndex, offsetBy: offset)
        let endIndex = data.index(startIndex, offsetBy: size)
        let stringData = data[startIndex..<endIndex]
        if let last = stringData.last, last == 0x00 {
            return String(decoding: stringData.dropLast(), as: UTF8.self)
        }
        return String(decoding: stringData, as: UTF8.self)
    }
    
    // MARK: - Internal Utilities
    
    /// Determines the length of a VarInt based on the leading zero bits of the first byte.
    private static func varIntLength(from byte: UInt8) -> Int {
        if byte & 0x80 != 0 { return 1 }
        else if byte & 0x40 != 0 { return 2 }
        else if byte & 0x20 != 0 { return 3 }
        else if byte & 0x10 != 0 { return 4 }
        else if byte & 0x08 != 0 { return 5 }
        else if byte & 0x04 != 0 { return 6 }
        else if byte & 0x02 != 0 { return 7 }
        else if byte & 0x01 != 0 { return 8 }
        return 0 // Invalid byte 0x00
    }

    private static func checkedEnd(
        offset: Int,
        length: Int,
        dataCount: Int,
        context: String
    ) throws -> Int {
        guard length >= 0 else {
            throw NativeBridgeError.demuxerFailed("Negative length in \(context)")
        }
        let (end, overflow) = offset.addingReportingOverflow(length)
        if overflow {
            throw NativeBridgeError.invalidMKV("Integer overflow while reading \(context)")
        }
        guard end <= dataCount else {
            throw NativeBridgeError.demuxerEOF
        }
        return end
    }

    private static func byte(at offset: Int, in data: Data) -> UInt8 {
        let index = data.index(data.startIndex, offsetBy: offset)
        return data[index]
    }
}
