import CoreMedia
import Foundation

public struct MatroskaTrackParser: Sendable {
    private let reader = EBMLReader()

    public init() {}

    public func parseTracks(data: Data) throws -> [MatroskaParsedTrack] {
        try children(in: data, bodyOffset: 0, bodySize: data.count).compactMap { child in
            guard child.header.id == EBMLElementID.trackEntry else { return nil }
            return try parseTrackEntry(data: data, payloadRange: child.payloadRange)
        }
    }

    private func parseTrackEntry(data: Data, payloadRange: Range<Int>) throws -> MatroskaParsedTrack {
        var number = 0
        var type = MediaTrackKind.unknown
        var codecID = "unknown"
        var track = MatroskaParsedTrack(number: number, type: type, codecID: codecID, codec: "unknown")
        try forEachChild(data: data, payloadRange: payloadRange) { child, range in
            switch child.id {
            case EBMLElementID.trackNumber:
                number = try readInt(data, range)
            case EBMLElementID.trackType:
                type = kind(try readInt(data, range))
            case EBMLElementID.codecID:
                codecID = try readString(data, range)
            case EBMLElementID.codecPrivate:
                track.codecPrivate = Data(data[range])
            case EBMLElementID.language:
                track.language = try readString(data, range)
            case EBMLElementID.name:
                track.name = try readString(data, range)
            case EBMLElementID.flagDefault:
                track.isDefault = try readUInt(data, range) != 0
            case EBMLElementID.flagForced:
                track.isForced = try readUInt(data, range) != 0
            case EBMLElementID.defaultDuration:
                let duration = try readUInt(data, range)
                _ = try reader.exactInt64(duration)
                track.defaultDuration = duration
            case EBMLElementID.video:
                track.video = try parseVideo(data: data, payloadRange: range)
            case EBMLElementID.audio:
                track.audio = try parseAudio(data: data, payloadRange: range)
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

    private func parseVideo(data: Data, payloadRange: Range<Int>) throws -> MatroskaVideoMetadata {
        var video = MatroskaVideoMetadata()
        try forEachChild(data: data, payloadRange: payloadRange) { child, range in
            switch child.id {
            case EBMLElementID.pixelWidth:
                video.width = try readInt(data, range)
            case EBMLElementID.pixelHeight:
                video.height = try readInt(data, range)
            case EBMLElementID.colour:
                video.hdr = try parseColour(data: data, payloadRange: range)
            default:
                break
            }
        }
        return video
    }

    private func parseColour(data: Data, payloadRange: Range<Int>) throws -> HDRMetadata {
        var primaries: Int?
        var transfer: Int?
        var matrix: Int?
        var bitDepth: Int?
        var light = ContentLightLevelMetadata()
        var mastering = MasteringDisplayMetadata()
        try forEachChild(data: data, payloadRange: payloadRange) { child, range in
            switch child.id {
            case EBMLElementID.primaries: primaries = try readInt(data, range)
            case EBMLElementID.transferCharacteristics: transfer = try readInt(data, range)
            case EBMLElementID.matrixCoefficients: matrix = try readInt(data, range)
            case EBMLElementID.bitsPerChannel: bitDepth = try readInt(data, range)
            case EBMLElementID.maxCLL: light.maxCLL = try readInt(data, range)
            case EBMLElementID.maxFALL: light.maxFALL = try readInt(data, range)
            case EBMLElementID.masteringMetadata:
                mastering = try parseMastering(data: data, payloadRange: range)
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

    private func parseMastering(data: Data, payloadRange: Range<Int>) throws -> MasteringDisplayMetadata {
        var metadata = MasteringDisplayMetadata()
        try forEachChild(data: data, payloadRange: payloadRange) { child, range in
            if child.id == EBMLElementID.masteringLuminanceMax {
                metadata.maxLuminance = try reader.readFloat(data: data, offset: range.lowerBound, size: range.count)
            } else if child.id == EBMLElementID.masteringLuminanceMin {
                metadata.minLuminance = try reader.readFloat(data: data, offset: range.lowerBound, size: range.count)
            }
        }
        return metadata
    }

    private func parseAudio(data: Data, payloadRange: Range<Int>) throws -> MatroskaAudioMetadata {
        var audio = MatroskaAudioMetadata()
        try forEachChild(data: data, payloadRange: payloadRange) { child, range in
            if child.id == EBMLElementID.channels {
                audio.channels = try readInt(data, range)
            } else if child.id == EBMLElementID.samplingFrequency {
                let sampleRate = try reader.finiteFloat(reader.readFloat(
                    data: data,
                    offset: range.lowerBound,
                    size: range.count
                ))
                let roundedRate = sampleRate.rounded()
                guard roundedRate > 0, roundedRate <= Double(CMTimeScale.max) else {
                    throw EBMLError.invalidMatroska("SamplingFrequency is outside the supported time scale")
                }
                audio.sampleRate = sampleRate
            } else if child.id == EBMLElementID.bitDepth {
                audio.bitDepth = try readInt(data, range)
            }
        }
        return audio
    }
}

private extension MatroskaTrackParser {
    func children(
        in data: Data,
        bodyOffset: Int,
        bodySize: Int
    ) throws -> [(header: EBMLElementHeader, payloadRange: Range<Int>)] {
        var children: [(header: EBMLElementHeader, payloadRange: Range<Int>)] = []
        let bodyRange = try reader.checkedRange(
            offset: bodyOffset,
            size: bodySize,
            parentEnd: data.count,
            dataCount: data.count
        )
        var offset = bodyRange.lowerBound
        while offset < bodyRange.upperBound {
            let header = try reader.readHeader(data: data, offset: offset)
            let range = try reader.payloadRange(
                for: header,
                elementOffset: offset,
                parentEnd: bodyRange.upperBound,
                dataCount: data.count
            )
            children.append((header, range))
            offset = range.upperBound
        }
        return children
    }

    func forEachChild(
        data: Data,
        payloadRange: Range<Int>,
        _ body: (EBMLElementHeader, Range<Int>) throws -> Void
    ) throws {
        var offset = payloadRange.lowerBound
        while offset < payloadRange.upperBound {
            let child = try reader.readHeader(data: data, offset: offset)
            let range = try reader.payloadRange(
                for: child,
                elementOffset: offset,
                parentEnd: payloadRange.upperBound,
                dataCount: data.count
            )
            try body(child, range)
            offset = range.upperBound
        }
    }

    func readUInt(_ data: Data, _ range: Range<Int>) throws -> UInt64 {
        try reader.readUInt(data: data, offset: range.lowerBound, size: range.count)
    }

    func readInt(_ data: Data, _ range: Range<Int>) throws -> Int {
        try reader.exactInt(readUInt(data, range))
    }

    func readString(_ data: Data, _ range: Range<Int>) throws -> String {
        try reader.readString(data: data, offset: range.lowerBound, size: range.count)
    }

    func kind(_ raw: Int) -> MediaTrackKind {
        raw == 1 ? .video : (raw == 2 ? .audio : (raw == 17 ? .subtitle : .unknown))
    }
}
