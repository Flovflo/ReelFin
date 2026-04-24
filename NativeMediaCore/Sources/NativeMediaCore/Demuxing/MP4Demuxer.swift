import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation

public actor MP4Demuxer: MediaDemuxer {
    private let url: URL
    private let readableURL: AVFoundationReadableMediaURL
    private var info: DemuxerStreamInfo?
    private var packetReader: MP4PacketReaderState?
    private var packetStartTime: CMTime?

    public init(url: URL, format: ContainerFormat = .mp4) throws {
        self.url = url
        self.readableURL = try AVFoundationReadableMediaURL(originalURL: url, format: format)
    }

    public func open() async throws -> DemuxerStreamInfo {
        if let info { return info }
        let asset = AVURLAsset(url: readableURL.assetURL)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)
        var mapped: [MediaTrack] = []
        mapped.reserveCapacity(tracks.count)
        for (index, track) in tracks.enumerated() {
            mapped.append(try await self.map(track: track, fallbackID: index + 1, duration: duration))
        }
        let streamInfo = DemuxerStreamInfo(
            container: readableURL.assetURL.pathExtension.lowercased() == "mov" ? .mov : .mp4,
            duration: duration,
            tracks: mapped,
            seekMap: SeekMap(duration: duration, isSeekable: true)
        )
        info = streamInfo
        return streamInfo
    }

    public func readNextPacket() async throws -> MediaPacket? {
        _ = try await open()
        try await startPacketReaderIfNeeded()
        guard var state = packetReader else { return nil }

        for _ in 0..<state.outputs.count {
            let index = state.nextOutputIndex % state.outputs.count
            state.nextOutputIndex = (index + 1) % state.outputs.count
            let trackOutput = state.outputs[index]
            if let sample = trackOutput.output.copyNextSampleBuffer(),
               let packet = try MP4SampleBufferPacketExtractor.packet(from: sample, trackID: trackOutput.trackID) {
                packetReader = state
                return packet
            }
        }

        packetReader = state
        switch state.reader.status {
        case .completed:
            return nil
        case .failed:
            throw MP4DemuxerError.readerFailed(state.reader.error?.localizedDescription ?? "unknown")
        case .cancelled:
            throw MP4DemuxerError.readerCancelled
        default:
            return nil
        }
    }

    public func seek(to time: CMTime) async throws {
        packetReader?.reader.cancelReading()
        packetReader = nil
        packetStartTime = time
    }

    private func map(track: AVAssetTrack, fallbackID: Int, duration: CMTime) async throws -> MediaTrack {
        let mediaType = track.mediaType
        let descriptions = try await track.load(.formatDescriptions)
        let formatDescription = descriptions.first
        let codec = formatDescription.map { fourCC(CMFormatDescriptionGetMediaSubType($0)) } ?? "unknown"
        let language = try? await track.load(.languageCode)
        let estimatedRate = try? await track.load(.estimatedDataRate)
        let bitrate = estimatedRate.map { Int($0) }
        let id = Int(track.trackID)
        let audio = audioMetadata(from: formatDescription)
        return MediaTrack(
            id: "\(id == 0 ? fallbackID : id)",
            trackId: id == 0 ? fallbackID : id,
            kind: kind(for: mediaType),
            codec: normalize(codec),
            codecID: codec,
            language: language,
            title: nil,
            isDefault: fallbackID == 1,
            codecPrivateData: formatDescription.flatMap { codecPrivateData(from: $0, codec: codec) },
            duration: duration,
            bitrate: bitrate,
            audioSampleRate: audio.sampleRate,
            audioChannels: audio.channels,
            audioBitDepth: audio.bitDepth
        )
    }

    private func kind(for mediaType: AVMediaType) -> MediaTrackKind {
        switch mediaType {
        case .video: return .video
        case .audio: return .audio
        case .subtitle, .text, .closedCaption: return .subtitle
        case .metadata: return .metadata
        default: return .unknown
        }
    }

    private func normalize(_ codec: String) -> String {
        switch codec.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "avc1", "h264": return "h264"
        case "hvc1", "hev1", "hevc", "dvh1", "dvhe": return "hevc"
        case "mp4a", "aac": return "aac"
        case "ac-3": return "ac3"
        case "ec-3": return "eac3"
        default: return codec.lowercased()
        }
    }

    private func fourCC(_ value: FourCharCode) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? "\(value)"
    }

    private func codecPrivateData(from description: CMFormatDescription, codec: String) -> Data? {
        guard
            let extensions = CMFormatDescriptionGetExtensions(description) as NSDictionary?,
            let atoms = extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] as? NSDictionary
        else {
            return nil
        }
        let preferredKeys = [codec, "avcC", "hvcC", "av1C"]
        for key in preferredKeys {
            if let data = atoms[key] as? Data {
                return data
            }
        }
        return nil
    }

    private func audioMetadata(from description: CMFormatDescription?) -> (sampleRate: Double?, channels: Int?, bitDepth: Int?) {
        guard
            let description,
            CMFormatDescriptionGetMediaType(description) == kCMMediaType_Audio,
            let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description)
        else {
            return (nil, nil, nil)
        }
        let bits = stream.pointee.mBitsPerChannel
        return (
            stream.pointee.mSampleRate == 0 ? nil : stream.pointee.mSampleRate,
            stream.pointee.mChannelsPerFrame == 0 ? nil : Int(stream.pointee.mChannelsPerFrame),
            bits == 0 ? nil : Int(bits)
        )
    }

    private func startPacketReaderIfNeeded() async throws {
        guard packetReader == nil else { return }
        let asset = AVURLAsset(url: readableURL.assetURL)
        let tracks = try await asset.load(.tracks)
        let duration = try await asset.load(.duration)
        let reader = try AVAssetReader(asset: asset)
        if let start = packetStartTime, start.isValid, duration.isValid {
            let remaining = CMTimeSubtract(duration, start)
            if remaining.isValid, remaining > .zero {
                reader.timeRange = CMTimeRange(start: start, duration: remaining)
            }
        }

        var outputs: [MP4TrackOutput] = []
        for track in tracks where track.mediaType == .video || track.mediaType == .audio {
            let output = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: outputSettings(for: track.mediaType)
            )
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { continue }
            reader.add(output)
            let trackID = Int(track.trackID) == 0 ? outputs.count + 1 : Int(track.trackID)
            outputs.append(MP4TrackOutput(trackID: trackID, output: output))
        }
        guard !outputs.isEmpty else { throw MP4DemuxerError.noPacketOutputs }
        guard reader.startReading() else {
            throw MP4DemuxerError.readerFailed(reader.error?.localizedDescription ?? "unknown")
        }
        packetReader = MP4PacketReaderState(reader: reader, outputs: outputs)
    }

    private func outputSettings(for mediaType: AVMediaType) -> [String: Any]? {
        switch mediaType {
        case .video:
            return [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ]
        case .audio:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        default:
            return nil
        }
    }
}

private struct MP4TrackOutput {
    let trackID: Int
    let output: AVAssetReaderTrackOutput
}

private struct MP4PacketReaderState {
    let reader: AVAssetReader
    let outputs: [MP4TrackOutput]
    var nextOutputIndex: Int = 0
}

private enum MP4DemuxerError: LocalizedError {
    case noPacketOutputs
    case readerFailed(String)
    case readerCancelled

    var errorDescription: String? {
        switch self {
        case .noPacketOutputs:
            return "MP4Demuxer could not create packet outputs for any audio or video track."
        case .readerFailed(let reason):
            return "MP4Demuxer AVAssetReader failed: \(reason)"
        case .readerCancelled:
            return "MP4Demuxer AVAssetReader was cancelled."
        }
    }
}
