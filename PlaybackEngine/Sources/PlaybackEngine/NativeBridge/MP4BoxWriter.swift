import Foundation
import Shared

/// Low-level binary utility to construct ISO Base Media File Format (ISO-BMFF) boxes (atoms),
/// used particularly for generating fragmented MP4 (fMP4) streams compatible with AVPlayer.
public struct MP4BoxWriter {
    
    // MARK: - Box Construction
    
    /// Writes an ISO-BMFF box with the given 4-character code (FourCC) and unpadded payload.
    /// The length prefix (4 bytes) is automatically computed and prepended.
    public static func writeBox(type: String, payload: Data = Data()) -> Data {
        guard type.utf8.count == 4 else {
            assertionFailure("MP4 Box type must be exactly 4 characters: '\(type)'")
            return Data()
        }
        
        var box = Data()
        box.reserveCapacity(8 + payload.count)
        // 4 bytes for length (size of header + payload)
        box.append(writeUInt32(UInt32(8 + payload.count)))
        
        // 4 bytes for type
        box.append(contentsOf: type.utf8)
        
        // Payload
        box.append(payload)
        return box
    }
    
    /// Writes a "Full Box" which is a standard box plus a 1-byte version and 3-byte flags.
    public static func writeFullBox(type: String, version: UInt8 = 0, flags: UInt32 = 0, payload: Data = Data()) -> Data {
        var fullPayload = Data()
        fullPayload.append(version)
        
        // Flags is 24 bits (3 bytes), extract from native UInt32 in big-endian byte order
        fullPayload.append(UInt8((flags >> 16) & 0xFF))
        fullPayload.append(UInt8((flags >> 8) & 0xFF))
        fullPayload.append(UInt8(flags & 0xFF))
        
        fullPayload.append(payload)
        return writeBox(type: type, payload: fullPayload)
    }
    
    // MARK: - Core Types
    
    public static func writeUInt32(_ value: UInt32) -> Data {
        var be = value.bigEndian
        return Data(bytes: &be, count: 4)
    }
    
    public static func writeUInt16(_ value: UInt16) -> Data {
        var be = value.bigEndian
        return Data(bytes: &be, count: 2)
    }
    
    public static func writeUInt64(_ value: UInt64) -> Data {
        var be = value.bigEndian
        return Data(bytes: &be, count: 8)
    }
    
    // MARK: - Common fMP4 Boxes (ftyp, moov)
    
    public static func writeFtyp(hasDolbyVision: Bool = false) -> Data {
        var payload = Data()
        payload.append(contentsOf: "iso5".utf8) // major brand
        payload.append(writeUInt32(512))         // minor version
        // Compatible brands: base fMP4 set + HEVC + optional DV
        let baseBrands = "iso5iso6mp41hvc1"
        payload.append(contentsOf: baseBrands.utf8)
        if hasDolbyVision {
            payload.append(contentsOf: "dby1".utf8)
        }
        return writeBox(type: "ftyp", payload: payload)
    }
    
    public static func writeMoov(
        tracks: [TrackInfo],
        duration: UInt64,
        timescale: UInt32 = 1000,
        sampleEntryType: String? = nil,
        dvConfig: DVConfig? = nil
    ) -> Data {
        var payload = writeMvhd(duration: duration, timescale: timescale)

        for track in tracks {
            let trackSET = (track.trackType == .video) ? sampleEntryType : nil
            let trackDV = (track.trackType == .video) ? dvConfig : nil
            payload.append(writeTrak(track: track, duration: duration, timescale: timescale, sampleEntryType: trackSET, dvConfig: trackDV))
        }
        
        payload.append(writeMvex(tracks: tracks))
        return writeBox(type: "moov", payload: payload)
    }
    
    // MARK: - Box Builders (Internal/Detailed)
    
    private static func writeMvhd(duration: UInt64, timescale: UInt32) -> Data {
        var payload = Data()
        payload.append(writeUInt64(0)) // creation_time
        payload.append(writeUInt64(0)) // modification_time
        payload.append(writeUInt32(timescale))
        payload.append(writeUInt64(duration))
        payload.append(writeUInt32(0x00010000)) // rate 1.0
        payload.append(writeUInt16(0x0100))     // volume 1.0
        payload.append(writeUInt16(0))          // reserved
        payload.append(writeUInt32(0))          // reserved
        payload.append(writeUInt32(0))          // reserved
        payload.append(contentsOf: [
            0x00, 0x01, 0x00, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, // identity matrix
            0, 0, 0, 0, 0x00, 0x01, 0x00, 0x00, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0x40, 0x00, 0x00, 0x00
        ])
        payload.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]) // pre_defined
        payload.append(writeUInt32(0xFFFFFFFF)) // next_track_id
        
        return writeFullBox(type: "mvhd", version: 1, payload: payload)
    }
    
    private static func writeTrak(track: TrackInfo, duration: UInt64, timescale: UInt32, sampleEntryType: String? = nil, dvConfig: DVConfig? = nil) -> Data {
        var payload = writeTkhd(track: track, duration: duration)
        payload.append(writeMdia(track: track, duration: duration, timescale: timescale, sampleEntryType: sampleEntryType, dvConfig: dvConfig))
        return writeBox(type: "trak", payload: payload)
    }
    
    private static func writeTkhd(track: TrackInfo, duration: UInt64) -> Data {
        var payload = Data()
        payload.append(writeUInt64(0)) // creation
        payload.append(writeUInt64(0)) // modification
        payload.append(writeUInt32(UInt32(track.id))) // track_ID
        payload.append(writeUInt32(0)) // reserved
        payload.append(writeUInt64(duration))
        payload.append(writeUInt32(0)) // reserved
        payload.append(writeUInt32(0)) // reserved
        payload.append(writeUInt16(0)) // layer
        payload.append(writeUInt16(0)) // alternate_group
        payload.append(writeUInt16(track.trackType == .audio ? 0x0100 : 0)) // volume
        payload.append(writeUInt16(0)) // reserved
        payload.append(contentsOf: [   // matrix
            0x00, 0x01, 0x00, 0x00, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0x00, 0x01, 0x00, 0x00, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0x40, 0x00, 0x00, 0x00
        ])
        
        let width = track.trackType == .video ? (track.width ?? 0) : 0
        let height = track.trackType == .video ? (track.height ?? 0) : 0
        payload.append(writeUInt32(UInt32(width << 16)))
        payload.append(writeUInt32(UInt32(height << 16)))
        
        return writeFullBox(type: "tkhd", version: 1, flags: 0x000003, payload: payload) // track_in_movie | track_in_preview
    }
    
    private static func writeMdia(track: TrackInfo, duration: UInt64, timescale: UInt32, sampleEntryType: String? = nil, dvConfig: DVConfig? = nil) -> Data {
        var payload = writeMdhd(duration: duration, timescale: timescale)
        payload.append(writeHdlr(trackType: track.trackType))
        payload.append(writeMinf(track: track, sampleEntryType: sampleEntryType, dvConfig: dvConfig))
        return writeBox(type: "mdia", payload: payload)
    }
    
    private static func writeMdhd(duration: UInt64, timescale: UInt32) -> Data {
        var payload = Data()
        payload.append(writeUInt64(0)) // creation
        payload.append(writeUInt64(0)) // mod
        payload.append(writeUInt32(timescale))
        payload.append(writeUInt64(duration))
        payload.append(writeUInt16(0x55C4)) // language (und)
        payload.append(writeUInt16(0)) // pre_defined
        return writeFullBox(type: "mdhd", version: 1, payload: payload)
    }
    
    private static func writeHdlr(trackType: TrackInfo.TrackType) -> Data {
        var payload = Data()
        payload.append(writeUInt32(0)) // pre_defined
        
        let handlerCode: String
        let handlerName: String
        switch trackType {
        case .video:
            handlerCode = "vide"
            handlerName = "VideoHandler"
        case .audio:
            handlerCode = "soun"
            handlerName = "SoundHandler"
        case .subtitle:
            handlerCode = "sbtl"
            handlerName = "SubtitleHandler"
        }
        
        payload.append(contentsOf: handlerCode.utf8)
        payload.append(contentsOf: [0,0,0,0, 0,0,0,0, 0,0,0,0]) // reserved (12 bytes)
        payload.append(contentsOf: handlerName.utf8)
        payload.append(0) // null-terminated
        
        return writeFullBox(type: "hdlr", payload: payload)
    }
    
    private static func writeMinf(track: TrackInfo, sampleEntryType: String? = nil, dvConfig: DVConfig? = nil) -> Data {
        var payload = Data()
        if track.trackType == .video {
            payload.append(writeFullBox(type: "vmhd", flags: 1, payload: Data(repeating: 0, count: 8))) // graphicsmode/opcolor
        } else if track.trackType == .audio {
            payload.append(writeFullBox(type: "smhd", payload: writeUInt32(0))) // balance/reserved
        }
        // Data info box (dinf -> dref -> url)
        let dref = writeFullBox(type: "dref", payload: writeUInt32(1) + writeFullBox(type: "url ", flags: 1))
        payload.append(writeBox(type: "dinf", payload: dref))
        payload.append(writeStbl(track: track, sampleEntryType: sampleEntryType, dvConfig: dvConfig))
        return writeBox(type: "minf", payload: payload)
    }
    
    private static func writeStbl(track: TrackInfo, sampleEntryType: String? = nil, dvConfig: DVConfig? = nil) -> Data {
        var payload = writeStsd(track: track, sampleEntryType: sampleEntryType, dvConfig: dvConfig)
        payload.append(writeFullBox(type: "stts", payload: writeUInt32(0)))
        payload.append(writeFullBox(type: "stsc", payload: writeUInt32(0)))
        payload.append(writeFullBox(type: "stsz", payload: writeUInt32(0) + writeUInt32(0)))
        payload.append(writeFullBox(type: "stco", payload: writeUInt32(0)))
        return writeBox(type: "stbl", payload: payload)
    }
    
    // MARK: - Codec Config Boxes

    /// Wraps an HEVCDecoderConfigurationRecord in a `hvcC` box (ISO 14496-15).
    /// Ensures lengthSizeMinusOne is set to 3 (4-byte NALU lengths) for fMP4 compatibility.
    public static func writeHvcCBox(codecPrivate: Data) -> Data {
        var config = codecPrivate
        if config.count >= 22 {
            // Byte 21 bits 0-1 = lengthSizeMinusOne; force to 3 (4-byte NALU length prefixes)
            config[21] = (config[21] & 0xFC) | 0x03
        }
        return writeBox(type: "hvcC", payload: config)
    }

    /// Wraps an AVCDecoderConfigurationRecord in an `avcC` box (ISO 14496-15).
    public static func writeAvcCBox(codecPrivate: Data) -> Data {
        return writeBox(type: "avcC", payload: codecPrivate)
    }

    /// Writes a `dvcC` box (Dolby Vision Configuration Record) for DV Profile 8.
    /// Structure: 1 byte version + 3 bytes packed fields.
    /// See ETSI GS CCM 001 / Dolby Vision Streams Within the ISO Base Media File Format.
    public static func writeDvcCBox(profile: Int, level: Int, compatibilityId: Int) -> Data {
        var payload = Data()
        // dv_version_major = 1, dv_version_minor = 0
        payload.append(1)  // dv_version_major
        payload.append(0)  // dv_version_minor
        // Packed 3 bytes:
        //   dv_profile (7 bits) | dv_level (6 bits) | rpu_present_flag (1 bit) |
        //   el_present_flag (1 bit) | bl_present_flag (1 bit) |
        //   dv_bl_signal_compatibility_id (4 bits) | reserved (4 bits)
        let profileBits = UInt32(profile & 0x7F) << 17
        let levelBits = UInt32(level & 0x3F) << 11
        let rpuPresent: UInt32 = 1 << 10  // RPU always present for Profile 8
        let elPresent: UInt32 = 0 << 9    // No enhancement layer for Profile 8
        let blPresent: UInt32 = 1 << 8    // Base layer present
        let compatBits = UInt32(compatibilityId & 0x0F) << 4
        // reserved = 0 (4 bits)
        let packed = profileBits | levelBits | rpuPresent | elPresent | blPresent | compatBits
        payload.append(UInt8((packed >> 16) & 0xFF))
        payload.append(UInt8((packed >> 8) & 0xFF))
        payload.append(UInt8(packed & 0xFF))
        return writeBox(type: "dvcC", payload: payload)
    }

    // MARK: - HDR Metadata Boxes

    /// Writes a `colr` box (nclx colour information, ISO 14496-12 §12.1.5).
    /// primaries/transfer/matrix values from ITU-T H.273 / ISO 23001-8.
    public static func writeColrBox(primaries: UInt16, transfer: UInt16, matrix: UInt16, fullRange: Bool = false) -> Data {
        var payload = Data()
        payload.append(contentsOf: "nclx".utf8)
        payload.append(contentsOf: [UInt8(primaries >> 8), UInt8(primaries & 0xFF)])
        payload.append(contentsOf: [UInt8(transfer >> 8), UInt8(transfer & 0xFF)])
        payload.append(contentsOf: [UInt8(matrix >> 8), UInt8(matrix & 0xFF)])
        payload.append(fullRange ? 0x80 : 0x00) // full_range_flag in MSB; 7 reserved bits
        return writeBox(type: "colr", payload: payload)
    }

    /// Writes a `mdcv` box (Mastering Display Color Volume, SMPTE ST 2086 / ISO 14496-12).
    /// Primaries are passed in 1/50000 units; luminance in 1/10000 nits.
    /// If exact primaries are unknown, standard BT.2020 D65 values are used for primaries = 9.
    public static func writeMdcvBox(colourPrimaries: Int?, luminanceMax: Double, luminanceMin: Double) -> Data {
        var payload = Data()
        // Display primaries: R, G, B x/y each 16-bit in units of 1/50000
        // Use BT.2020 standard primaries when not specified (colourPrimaries == 9)
        // or P3-D65 (colourPrimaries == 12)
        let primaries: [(x: UInt16, y: UInt16)]
        switch colourPrimaries {
        case 9: // BT.2020
            primaries = [(34000, 16000), (13250, 34500), (7500, 3000)]
        case 12: // Display P3
            primaries = [(34000, 16000), (13250, 34500), (7500, 3000)]
        default: // BT.709 / unknown — use BT.709 primaries (ITU-R BT.709-6, units 1/50000)
            primaries = [(32000, 16500), (15000, 30000), (7500, 3000)]
        }
        for (x, y) in primaries {
            payload.append(contentsOf: [UInt8(x >> 8), UInt8(x & 0xFF)])
            payload.append(contentsOf: [UInt8(y >> 8), UInt8(y & 0xFF)])
        }
        // White point: D65 = (0.3127, 0.3290) → 15635, 16450
        payload.append(contentsOf: [0x3D, 0x13]) // 15635
        payload.append(contentsOf: [0x40, 0x42]) // 16450
        // Max/min luminance in 1/10000 nits
        let maxLum = UInt32(luminanceMax * 10000.0)
        let minLum = UInt32(luminanceMin * 10000.0)
        payload.append(contentsOf: [
            UInt8(maxLum >> 24), UInt8((maxLum >> 16) & 0xFF),
            UInt8((maxLum >> 8) & 0xFF), UInt8(maxLum & 0xFF)
        ])
        payload.append(contentsOf: [
            UInt8(minLum >> 24), UInt8((minLum >> 16) & 0xFF),
            UInt8((minLum >> 8) & 0xFF), UInt8(minLum & 0xFF)
        ])
        return writeBox(type: "mdcv", payload: payload)
    }

    /// Writes a `clli` box (Content Light Level Info, SMPTE ST 2086 / ISO 14496-12).
    public static func writeClliBox(maxCLL: UInt16, maxFALL: UInt16) -> Data {
        var payload = Data()
        payload.append(contentsOf: [UInt8(maxCLL >> 8), UInt8(maxCLL & 0xFF)])
        payload.append(contentsOf: [UInt8(maxFALL >> 8), UInt8(maxFALL & 0xFF)])
        return writeBox(type: "clli", payload: payload)
    }

    // MARK: - Sample Description Box

    /// DV configuration to embed in the sample entry when DV is enabled.
    public struct DVConfig {
        public let profile: Int
        public let level: Int
        public let compatibilityId: Int
    }

    static func writeStsd(track: TrackInfo, sampleEntryType: String? = nil, dvConfig: DVConfig? = nil) -> Data {
        var payload = writeUInt32(1) // entry_count

        var sampleEntry = Data()
        sampleEntry.append(contentsOf: [0, 0, 0, 0, 0, 0]) // reserved (6 bytes)
        sampleEntry.append(writeUInt16(1))                  // data_reference_index

        let typeCode: String

        if track.trackType == .video {
            let isHEVC = track.codecName == "hevc" || track.codecID.lowercased().contains("hevc")

            // Explicit override takes priority (used by packaging modes A/B/C).
            // Without override: backward-compatible auto-detection (dvConfig → dvh1).
            if let override = sampleEntryType {
                typeCode = override
            } else if dvConfig != nil {
                typeCode = "dvh1"
            } else if isHEVC {
                typeCode = "hvc1"
            } else {
                typeCode = "avc1"
            }

            sampleEntry.append(writeUInt16(0))  // pre_defined
            sampleEntry.append(writeUInt16(0))  // reserved
            sampleEntry.append(contentsOf: [0,0,0,0, 0,0,0,0, 0,0,0,0]) // pre_defined[3] (12 bytes)
            sampleEntry.append(writeUInt16(UInt16(track.width ?? 0)))
            sampleEntry.append(writeUInt16(UInt16(track.height ?? 0)))
            sampleEntry.append(writeUInt32(0x00480000)) // horizresolution 72 dpi (16.16 fixed)
            sampleEntry.append(writeUInt32(0x00480000)) // vertresolution  72 dpi
            sampleEntry.append(writeUInt32(0))          // reserved
            sampleEntry.append(writeUInt16(1))          // frame_count
            sampleEntry.append(Data(repeating: 0, count: 32)) // compressorname (32 bytes)
            sampleEntry.append(writeUInt16(0x0018))     // depth (24-bit colour)
            sampleEntry.append(writeUInt16(0xFFFF))     // pre_defined = -1

            // --- Codec configuration box (hvcC / avcC) ---
            if let config = track.codecPrivate {
                if isHEVC || typeCode == "dvh1" || typeCode == "dvhe" {
                    sampleEntry.append(writeHvcCBox(codecPrivate: config))
                } else {
                    sampleEntry.append(writeAvcCBox(codecPrivate: config))
                }
            } else {
                AppLog.playback.warning("MP4BoxWriter: No codec private data for video track \(track.id) — decoder may fail to initialize.")
            }

            // --- Dolby Vision configuration (dvcC) box ---
            if let dv = dvConfig {
                sampleEntry.append(writeDvcCBox(
                    profile: dv.profile,
                    level: dv.level,
                    compatibilityId: dv.compatibilityId
                ))
            }

            // --- Colour information (colr box) ---
            // Always write for video; default to BT.709 SDR when no info available
            let primaries = UInt16(track.colourPrimaries ?? 1)  // 1=BT.709, 9=BT.2020
            let transfer  = UInt16(track.transferCharacteristic ?? 1) // 1=BT.709, 16=PQ, 18=HLG
            let matrix    = UInt16(track.matrixCoefficients ?? 1)     // 1=BT.709, 9=BT.2020 nc
            sampleEntry.append(writeColrBox(primaries: primaries, transfer: transfer, matrix: matrix))

            // --- HDR10 mastering display (mdcv) and content light level (clli) ---
            if let lumMax = track.masteringLuminanceMax,
               let lumMin = track.masteringLuminanceMin {
                sampleEntry.append(writeMdcvBox(
                    colourPrimaries: track.colourPrimaries,
                    luminanceMax: lumMax,
                    luminanceMin: lumMin
                ))
            }
            if let cll = track.maxCLL, let fall = track.maxFALL {
                sampleEntry.append(writeClliBox(maxCLL: UInt16(cll), maxFALL: UInt16(fall)))
            }

        } else {
            // Audio sample entry
            let codecLower = track.codecName.lowercased()
            if codecLower == "eac3" || codecLower == "ec3" {
                typeCode = "ec-3"
            } else if codecLower == "ac3" {
                typeCode = "ac-3"
            } else {
                typeCode = "mp4a"
            }

            let sanitizedChannels = max(1, min(track.channels ?? 2, 16))
            let requestedSampleRate = track.sampleRate ?? 48_000
            let sanitizedSampleRate = max(8_000, min(requestedSampleRate, 192_000))

            sampleEntry.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0]) // reserved (8 bytes)
            sampleEntry.append(writeUInt16(UInt16(sanitizedChannels)))         // channelcount
            sampleEntry.append(writeUInt16(16))                               // samplesize (always 16)
            sampleEntry.append(writeUInt16(0))                                // pre_defined
            sampleEntry.append(writeUInt16(0))                                // reserved
            sampleEntry.append(writeUInt32(UInt32(sanitizedSampleRate << 16))) // samplerate (16.16)

            // Codec-specific config box
            if typeCode == "ec-3" {
                sampleEntry.append(writeDec3Box(channels: sanitizedChannels, sampleRate: sanitizedSampleRate))
            } else if typeCode == "ac-3" {
                sampleEntry.append(writeDac3Box(channels: sanitizedChannels, sampleRate: sanitizedSampleRate))
            } else if typeCode == "mp4a", let config = track.codecPrivate {
                sampleEntry.append(writeEsdsBox(audioSpecificConfig: config))
            }
        }

        payload.append(writeBox(type: typeCode, payload: sampleEntry))
        return writeFullBox(type: "stsd", payload: payload)
    }

    // MARK: - AAC esds Box

    /// Wraps an AudioSpecificConfig in a minimal `esds` box (ISO 14496-1 ES_Descriptor).
    private static func writeEsdsBox(audioSpecificConfig asc: Data) -> Data {
        // ES_Descriptor tag = 0x03
        // DecoderConfigDescriptor tag = 0x04
        // DecoderSpecificInfo tag = 0x05
        // SLConfigDescriptor tag = 0x06
        func expandableClassSize(_ size: Int) -> Data {
            // MPEG-4 descriptor length encoding (can be 1-4 bytes)
            var d = Data()
            if size < 0x80 {
                d.append(UInt8(size))
            } else {
                d.append(UInt8(((size >> 21) & 0x7F) | 0x80))
                d.append(UInt8(((size >> 14) & 0x7F) | 0x80))
                d.append(UInt8(((size >> 7) & 0x7F) | 0x80))
                d.append(UInt8(size & 0x7F))
            }
            return d
        }

        // DecoderSpecificInfo
        var dsi = Data([0x05]) // tag
        dsi.append(expandableClassSize(asc.count))
        dsi.append(asc)

        // SLConfigDescriptor (predefined = 2)
        let slc = Data([0x06, 0x01, 0x02])

        // DecoderConfigDescriptor
        var dcd = Data([0x04])
        var dcdPayload = Data()
        dcdPayload.append(0x40)         // objectTypeIndication: Audio ISO/IEC 14496-3
        dcdPayload.append(0x15)         // streamType (audio=0x15), upstream=0, reserved=1
        dcdPayload.append(contentsOf: [0x00, 0x00, 0x00]) // bufferSizeDB
        dcdPayload.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // maxBitrate
        dcdPayload.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // avgBitrate
        dcdPayload.append(dsi)
        dcd.append(expandableClassSize(dcdPayload.count))
        dcd.append(dcdPayload)

        // ES_Descriptor
        var esDesc = Data([0x03])
        var esPayload = Data()
        esPayload.append(contentsOf: [0x00, 0x01]) // ES_ID
        esPayload.append(0x00)                     // streamDependenceFlag etc.
        esPayload.append(dcd)
        esPayload.append(slc)
        esDesc.append(expandableClassSize(esPayload.count))
        esDesc.append(esPayload)

        return writeFullBox(type: "esds", payload: esDesc)
    }
    
    // MARK: - E-AC-3 / AC-3 Configuration Boxes

    /// Writes a `dec3` box (E-AC-3 Specific Box, ETSI TS 102 366 Annex F.6).
    /// Minimal valid configuration describing one independent substream.
    public static func writeDec3Box(channels: Int, sampleRate: Int) -> Data {
        // dec3 structure:
        //   data_rate (13 bits) | num_ind_sub (3 bits) = 16 bits
        //   per independent substream:
        //     fscod (2) | bsid (5) | reserved (1) | asvc (1) | bsmod (3) | acmod (3) | lfeon (1) |
        //     reserved (3) | num_dep_sub (4) | if num_dep_sub > 0: chan_loc (9) else: reserved (1)
        //     = 24 bits if no dependent sub, 33 bits if dependent sub

        // Map channel count to acmod + lfeon
        let (acmod, lfeon): (UInt8, UInt8) = {
            switch channels {
            case 1:  return (1, 0)   // C
            case 2:  return (2, 0)   // L R
            case 3:  return (3, 0)   // L C R
            case 4:  return (7, 0)   // L C R S (3/1)
            case 5:  return (7, 0)   // L C R Ls Rs (approximate)
            case 6:  return (7, 1)   // 5.1
            case 7:  return (7, 1)   // 6.1 (approximate as 5.1 + dep sub)
            case 8:  return (7, 1)   // 7.1 → 5.1 base + dependent substream
            default: return (7, 1)   // default to 5.1
            }
        }()

        // For 7.1: one independent 5.1 substream + one dependent substream with Lrs/Rrs
        let has71 = channels >= 7
        let numIndSub: UInt8 = 0  // 0 = one independent substream (value is num_ind_sub - 1)
        let dataRate: UInt16 = 0  // 0 = unknown data rate

        var payload = Data()

        // First 16 bits: data_rate (13) | num_ind_sub (3)
        let word0 = (UInt16(dataRate) << 3) | UInt16(numIndSub & 0x07)
        payload.append(writeUInt16(word0))

        // Independent substream descriptor (24 bits without dep sub, 33 with)
        let fscod: UInt8 = (sampleRate == 44100) ? 1 : (sampleRate == 32000 ? 2 : 0) // 0=48kHz
        let bsid: UInt8 = 16  // E-AC-3
        let bsmod: UInt8 = 0  // complete main
        let numDepSub: UInt8 = has71 ? 1 : 0

        // Pack: fscod(2) | bsid(5) | reserved(1) | asvc(1) | bsmod(3) | acmod(3) | lfeon(1)
        //     | reserved(3) | num_dep_sub(4) | [chan_loc(9) or reserved(1)]
        var bits: UInt64 = 0
        bits = (bits << 2) | UInt64(fscod & 0x03)
        bits = (bits << 5) | UInt64(bsid & 0x1F)
        bits = (bits << 1) | 0  // reserved
        bits = (bits << 1) | 0  // asvc
        bits = (bits << 3) | UInt64(bsmod & 0x07)
        bits = (bits << 3) | UInt64(acmod & 0x07)
        bits = (bits << 1) | UInt64(lfeon & 0x01)
        bits = (bits << 3) | 0  // reserved
        bits = (bits << 4) | UInt64(numDepSub & 0x0F)

        if has71 {
            // chan_loc for Lrs/Rrs (back surround pair) = bit 1 = 0x002
            let chanLoc: UInt16 = 0x002
            bits = (bits << 9) | UInt64(chanLoc & 0x1FF)
            // Total: 2+5+1+1+3+3+1+3+4+9 = 32 bits = 4 bytes
            payload.append(UInt8((bits >> 24) & 0xFF))
            payload.append(UInt8((bits >> 16) & 0xFF))
            payload.append(UInt8((bits >> 8) & 0xFF))
            payload.append(UInt8(bits & 0xFF))
        } else {
            bits = (bits << 1) | 0  // reserved
            // Total: 2+5+1+1+3+3+1+3+4+1 = 24 bits = 3 bytes
            payload.append(UInt8((bits >> 16) & 0xFF))
            payload.append(UInt8((bits >> 8) & 0xFF))
            payload.append(UInt8(bits & 0xFF))
        }

        return writeBox(type: "dec3", payload: payload)
    }

    /// Writes a `dac3` box (AC-3 Specific Box, ETSI TS 102 366 Annex F.4).
    public static func writeDac3Box(channels: Int, sampleRate: Int) -> Data {
        // dac3 = 24 bits packed:
        //   fscod (2) | bsid (5) | bsmod (3) | acmod (3) | lfeon (1) | bit_rate_code (5) | reserved (5)

        let (acmod, lfeon): (UInt8, UInt8) = {
            switch channels {
            case 1:  return (1, 0)
            case 2:  return (2, 0)
            case 6:  return (7, 1)   // 5.1
            default: return (7, 1)
            }
        }()

        let fscod: UInt8 = (sampleRate == 44100) ? 1 : (sampleRate == 32000 ? 2 : 0)
        let bsid: UInt8 = 8  // AC-3
        let bsmod: UInt8 = 0
        let bitRateCode: UInt8 = 15  // 448 kbps (common for 5.1)

        var bits: UInt32 = 0
        bits = (bits << 2) | UInt32(fscod & 0x03)
        bits = (bits << 5) | UInt32(bsid & 0x1F)
        bits = (bits << 3) | UInt32(bsmod & 0x07)
        bits = (bits << 3) | UInt32(acmod & 0x07)
        bits = (bits << 1) | UInt32(lfeon & 0x01)
        bits = (bits << 5) | UInt32(bitRateCode & 0x1F)
        bits = (bits << 5) | 0  // reserved

        var payload = Data()
        payload.append(UInt8((bits >> 16) & 0xFF))
        payload.append(UInt8((bits >> 8) & 0xFF))
        payload.append(UInt8(bits & 0xFF))

        return writeBox(type: "dac3", payload: payload)
    }

    private static func writeMvex(tracks: [TrackInfo]) -> Data {
        var payload = Data()
        for track in tracks {
            var trex = Data()
            trex.append(writeUInt32(UInt32(track.id))) // track_ID
            trex.append(writeUInt32(1)) // default_sample_description_index
            trex.append(writeUInt32(0)) // default_sample_duration
            trex.append(writeUInt32(0)) // default_sample_size
            trex.append(writeUInt32(0)) // default_sample_flags
            payload.append(writeFullBox(type: "trex", payload: trex))
        }
        return writeBox(type: "mvex", payload: payload)
    }
}
