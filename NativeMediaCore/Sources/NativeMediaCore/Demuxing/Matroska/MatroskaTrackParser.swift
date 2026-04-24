import Foundation

public struct MatroskaTrackParser: Sendable {
    private let reader = EBMLReader()

    public init() {}

    public func parseTracks(data: Data) throws -> [MatroskaParsedTrack] {
        try children(in: data, bodyOffset: 0, bodySize: data.count).compactMap { header in
            guard header.id == EBMLElementID.trackEntry else { return nil }
            return try parseTrackEntry(data: data, header: header)
        }
    }

    private func parseTrackEntry(data: Data, header: EBMLElementHeader) throws -> MatroskaParsedTrack {
        var number = 0
        var type = MediaTrackKind.unknown
        var codecID = "unknown"
        var track = MatroskaParsedTrack(number: number, type: type, codecID: codecID, codec: "unknown")
        try forEachChild(data: data, header: header) { child in
            switch child.id {
            case EBMLElementID.trackNumber:
                number = Int(try readUInt(data, child))
            case EBMLElementID.trackType:
                type = kind(Int(try readUInt(data, child)))
            case EBMLElementID.codecID:
                codecID = try readString(data, child)
            case EBMLElementID.codecPrivate:
                track.codecPrivate = Data(data[child.payloadOffset..<payloadEnd(child)])
            case EBMLElementID.language:
                track.language = try readString(data, child)
            case EBMLElementID.name:
                track.name = try readString(data, child)
            case EBMLElementID.flagDefault:
                track.isDefault = try readUInt(data, child) != 0
            case EBMLElementID.flagForced:
                track.isForced = try readUInt(data, child) != 0
            case EBMLElementID.defaultDuration:
                track.defaultDuration = try readUInt(data, child)
            case EBMLElementID.video:
                track.video = try parseVideo(data: data, header: child)
            case EBMLElementID.audio:
                track.audio = try parseAudio(data: data, header: child)
            default:
                break
            }
        }
        track.number = number
        track.type = type
        track.codecID = codecID
        track.codec = MatroskaCodecMapper.normalizedCodec(codecID)
        return track
    }

    private func parseVideo(data: Data, header: EBMLElementHeader) throws -> MatroskaVideoMetadata {
        var video = MatroskaVideoMetadata()
        try forEachChild(data: data, header: header) { child in
            switch child.id {
            case EBMLElementID.pixelWidth:
                video.width = Int(try readUInt(data, child))
            case EBMLElementID.pixelHeight:
                video.height = Int(try readUInt(data, child))
            case EBMLElementID.colour:
                video.hdr = try parseColour(data: data, header: child)
            default:
                break
            }
        }
        return video
    }

    private func parseColour(data: Data, header: EBMLElementHeader) throws -> HDRMetadata {
        var primaries: Int?
        var transfer: Int?
        var matrix: Int?
        var bitDepth: Int?
        var light = ContentLightLevelMetadata()
        var mastering = MasteringDisplayMetadata()
        try forEachChild(data: data, header: header) { child in
            switch child.id {
            case EBMLElementID.primaries: primaries = Int(try readUInt(data, child))
            case EBMLElementID.transferCharacteristics: transfer = Int(try readUInt(data, child))
            case EBMLElementID.matrixCoefficients: matrix = Int(try readUInt(data, child))
            case EBMLElementID.bitsPerChannel: bitDepth = Int(try readUInt(data, child))
            case EBMLElementID.maxCLL: light.maxCLL = Int(try readUInt(data, child))
            case EBMLElementID.maxFALL: light.maxFALL = Int(try readUInt(data, child))
            case EBMLElementID.masteringMetadata:
                mastering = try parseMastering(data: data, header: child)
            default: break
            }
        }
        let format: HDRFormat = transfer == 16 ? .hdr10 : (transfer == 18 ? .hlg : .unknown)
        return HDRMetadata(
            format: format,
            colorPrimaries: HDRMetadataMapper.primaries(matroska: primaries),
            transferFunction: HDRMetadataMapper.transfer(matroska: transfer),
            matrixCoefficients: HDRMetadataMapper.matrix(matroska: matrix),
            bitDepth: bitDepth,
            masteringDisplay: mastering,
            contentLightLevel: light
        )
    }

    private func parseMastering(data: Data, header: EBMLElementHeader) throws -> MasteringDisplayMetadata {
        var metadata = MasteringDisplayMetadata()
        try forEachChild(data: data, header: header) { child in
            if child.id == EBMLElementID.masteringLuminanceMax {
                metadata.maxLuminance = try reader.readFloat(data: data, offset: child.payloadOffset, size: Int(child.size ?? 0))
            } else if child.id == EBMLElementID.masteringLuminanceMin {
                metadata.minLuminance = try reader.readFloat(data: data, offset: child.payloadOffset, size: Int(child.size ?? 0))
            }
        }
        return metadata
    }

    private func parseAudio(data: Data, header: EBMLElementHeader) throws -> MatroskaAudioMetadata {
        var audio = MatroskaAudioMetadata()
        try forEachChild(data: data, header: header) { child in
            if child.id == EBMLElementID.channels {
                audio.channels = Int(try readUInt(data, child))
            } else if child.id == EBMLElementID.samplingFrequency {
                audio.sampleRate = try reader.readFloat(data: data, offset: child.payloadOffset, size: Int(child.size ?? 0))
            } else if child.id == EBMLElementID.bitDepth {
                audio.bitDepth = Int(try readUInt(data, child))
            }
        }
        return audio
    }
}

private extension MatroskaTrackParser {
    func children(in data: Data, bodyOffset: Int, bodySize: Int) throws -> [EBMLElementHeader] {
        var headers: [EBMLElementHeader] = []
        var offset = bodyOffset
        while offset < bodyOffset + bodySize {
            let header = try reader.readHeader(data: data, offset: offset)
            headers.append(header)
            offset = payloadEnd(header)
        }
        return headers
    }

    func forEachChild(data: Data, header: EBMLElementHeader, _ body: (EBMLElementHeader) throws -> Void) throws {
        var offset = header.payloadOffset
        while offset < payloadEnd(header) {
            let child = try reader.readHeader(data: data, offset: offset)
            try body(child)
            offset = payloadEnd(child)
        }
    }

    func readUInt(_ data: Data, _ header: EBMLElementHeader) throws -> UInt64 {
        try reader.readUInt(data: data, offset: header.payloadOffset, size: Int(header.size ?? 0))
    }

    func readString(_ data: Data, _ header: EBMLElementHeader) throws -> String {
        try reader.readString(data: data, offset: header.payloadOffset, size: Int(header.size ?? 0))
    }

    func payloadEnd(_ header: EBMLElementHeader) -> Int {
        header.payloadOffset + Int(header.size ?? 0)
    }

    func kind(_ raw: Int) -> MediaTrackKind {
        raw == 1 ? .video : (raw == 2 ? .audio : (raw == 17 ? .subtitle : .unknown))
    }
}
