import Foundation

enum HEVCCodecFamily {
    private static let identifiers = ["hevc", "h265", "hvc1", "hev1"]
    private static let sampleEntries: Set<String> = ["hvc1", "hev1", "dvh1", "dvhe"]

    static func contains(_ track: TrackInfo, effectiveSampleEntry: String? = nil) -> Bool {
        let identifierMatch = [track.codecName, track.codecID]
            .map { $0.lowercased() }
            .contains { value in identifiers.contains(where: value.contains) }
        return identifierMatch
            || effectiveSampleEntry.map(isHEVCSampleEntry) == true
    }

    static func sourceSampleEntry(for track: TrackInfo) -> String {
        let identifiers = [track.codecName, track.codecID].map { $0.lowercased() }
        return identifiers.contains(where: { $0.contains("hev1") }) ? "hev1" : "hvc1"
    }

    static func effectiveSampleEntry(
        for track: TrackInfo,
        requestedMode: DolbyVisionPackagingMode,
        hasDolbyVision: Bool
    ) -> String {
        if hasDolbyVision, requestedMode == .dvProfile81Compatible {
            return "hvc1"
        }
        return sourceSampleEntry(for: track)
    }

    static func isHEVCSampleEntry(_ value: String) -> Bool {
        sampleEntries.contains(value.lowercased())
    }
}

/// A checked RFC 6381 / ISO/IEC 14496-15 Annex E projection of the
/// general profile/tier/level prefix in an HEVCDecoderConfigurationRecord.
struct HEVCCodecParameter: Sendable, Equatable {
    let sampleEntry: String
    let profileSpace: Int
    let profileIDC: Int
    let compatibilityFlags: UInt32
    let highTier: Bool
    let levelIDC: Int
    let constraintBytes: [UInt8]

    init?(configurationRecord: Data, sampleEntry: String) {
        guard sampleEntry == "hvc1" || sampleEntry == "hev1" else { return nil }
        guard Self.hasValidStructure(configurationRecord, sampleEntry: sampleEntry) else { return nil }

        let profileTier = configurationRecord[1]
        self.sampleEntry = sampleEntry
        self.profileSpace = Int((profileTier >> 6) & 0x03)
        self.profileIDC = Int(profileTier & 0x1F)
        self.highTier = (profileTier & 0x20) != 0
        self.levelIDC = Int(configurationRecord[12])

        let storedCompatibility = UInt32(configurationRecord[2]) << 24
            | UInt32(configurationRecord[3]) << 16
            | UInt32(configurationRecord[4]) << 8
            | UInt32(configurationRecord[5])
        self.compatibilityFlags = Self.reverseBits(storedCompatibility)

        var constraints = Array(configurationRecord[6...11])
        while constraints.last == 0 {
            constraints.removeLast()
        }
        self.constraintBytes = constraints
    }

    static func hasValidStructure(_ record: Data, sampleEntry: String) -> Bool {
        let fixedHeaderSize = 23
        let completeOutOfBandEntries: Set<String> = ["hvc1", "dvh1"]
        let inBandEntries: Set<String> = ["hev1", "dvhe"]
        guard completeOutOfBandEntries.contains(sampleEntry)
                || inBandEntries.contains(sampleEntry) else { return false }
        guard record.count >= fixedHeaderSize, record[0] == 1 else { return false }
        guard record[13] & 0xF0 == 0xF0 else { return false }
        guard record[15] & 0xFC == 0xFC, record[16] & 0xFC == 0xFC else { return false }
        guard record[17] & 0xF8 == 0xF8, record[18] & 0xF8 == 0xF8 else { return false }

        var cursor = fixedHeaderSize
        let numberOfArrays = Int(record[22])
        var completeParameterSetTypes: Set<Int> = []
        let requiresCompleteOutOfBandSets = completeOutOfBandEntries.contains(sampleEntry)
        for _ in 0..<numberOfArrays {
            // array_completeness/reserved/NAL_unit_type + numNalus
            guard cursor <= record.count - 3 else { return false }
            let arrayHeader = record[cursor]
            guard arrayHeader & 0x40 == 0 else { return false }
            let arrayNALUnitType = Int(arrayHeader & 0x3F)
            cursor += 1
            let numberOfNALUnits = Int(record[cursor]) << 8 | Int(record[cursor + 1])
            cursor += 2
            if requiresCompleteOutOfBandSets {
                if (32...34).contains(arrayNALUnitType) {
                    guard arrayHeader & 0x80 != 0, numberOfNALUnits > 0 else { return false }
                    completeParameterSetTypes.insert(arrayNALUnitType)
                } else {
                    guard arrayHeader & 0x80 == 0 else { return false }
                }
            }

            for _ in 0..<numberOfNALUnits {
                guard cursor <= record.count - 2 else { return false }
                let nalUnitLength = Int(record[cursor]) << 8 | Int(record[cursor + 1])
                cursor += 2
                // An HEVC NAL unit contains a mandatory two-byte header. Accepting
                // zero/one-byte payloads would validate a structurally unusable hvcC.
                guard nalUnitLength >= 2 else { return false }
                guard cursor <= record.count - nalUnitLength else { return false }
                let nalHeader0 = record[cursor]
                let nalHeader1 = record[cursor + 1]
                guard nalHeader0 & 0x80 == 0 else { return false }
                guard Int((nalHeader0 >> 1) & 0x3F) == arrayNALUnitType else { return false }
                guard nalHeader1 & 0x07 != 0 else { return false }
                cursor += nalUnitLength
            }
        }

        // `hvcC` is a complete decoder configuration record; unexplained trailing
        // bytes indicate a count/length mismatch and are rejected fail-closed.
        guard cursor == record.count else { return false }
        if requiresCompleteOutOfBandSets {
            return completeParameterSetTypes == Set([32, 33, 34])
        }
        return true
    }

    var value: String {
        let profileSpacePrefix = ["", "A", "B", "C"][profileSpace]
        let tier = highTier ? "H" : "L"
        var result = String(
            format: "%@.%@%d.%X.%@%d",
            sampleEntry,
            profileSpacePrefix,
            profileIDC,
            compatibilityFlags,
            tier,
            levelIDC
        )
        for byte in constraintBytes {
            result += String(format: ".%02X", byte)
        }
        return result
    }

    private static func reverseBits(_ value: UInt32) -> UInt32 {
        var source = value
        var reversed: UInt32 = 0
        for _ in 0..<32 {
            reversed = (reversed << 1) | (source & 1)
            source >>= 1
        }
        return reversed
    }
}
