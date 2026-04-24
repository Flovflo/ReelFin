@preconcurrency import AVFoundation
import CoreMedia
import Foundation

public struct MP4SampleBufferTrackInfo: Equatable, Sendable {
    public var trackID: Int
    public var kind: MediaTrackKind
    public var codec: String
    public var sampleCount: Int
    public var firstPresentationTime: CMTime?
    public var firstDuration: CMTime?

    public init(
        trackID: Int,
        kind: MediaTrackKind,
        codec: String,
        sampleCount: Int,
        firstPresentationTime: CMTime?,
        firstDuration: CMTime?
    ) {
        self.trackID = trackID
        self.kind = kind
        self.codec = codec
        self.sampleCount = sampleCount
        self.firstPresentationTime = firstPresentationTime
        self.firstDuration = firstDuration
    }
}

public enum MP4SampleBufferReaderError: LocalizedError, Sendable, Equatable {
    case noReadableTracks
    case cannotAddOutput(String)
    case readerStartFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noReadableTracks:
            return "MP4 sample reader found no readable audio or video tracks."
        case .cannotAddOutput(let mediaType):
            return "MP4 sample reader could not add \(mediaType) output."
        case .readerStartFailed(let reason):
            return "MP4 sample reader failed to start: \(reason)"
        }
    }
}

public final class MP4SampleBufferReader: @unchecked Sendable {
    private let readableURL: AVFoundationReadableMediaURL
    private let asset: AVURLAsset

    public init(url: URL, format: ContainerFormat = .mp4) throws {
        self.readableURL = try AVFoundationReadableMediaURL(originalURL: url, format: format)
        self.asset = AVURLAsset(url: readableURL.assetURL)
    }

    public func inspectFirstSamples(maxSamplesPerTrack: Int = 3) async throws -> [MP4SampleBufferTrackInfo] {
        let tracks = try await asset.load(.tracks)
        let selected = tracks.filter { $0.mediaType == .video || $0.mediaType == .audio }
        guard !selected.isEmpty else { throw MP4SampleBufferReaderError.noReadableTracks }

        let reader = try AVAssetReader(asset: asset)
        var outputs: [(AVAssetTrack, AVAssetReaderTrackOutput)] = []
        for track in selected {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                throw MP4SampleBufferReaderError.cannotAddOutput(track.mediaType.rawValue)
            }
            reader.add(output)
            outputs.append((track, output))
        }
        guard reader.startReading() else {
            throw MP4SampleBufferReaderError.readerStartFailed(reader.error?.localizedDescription ?? "unknown")
        }
        defer { reader.cancelReading() }

        return outputs.map { track, output in
            var count = 0
            var firstPTS: CMTime?
            var firstDuration: CMTime?
            while count < maxSamplesPerTrack, let sample = output.copyNextSampleBuffer() {
                if firstPTS == nil {
                    firstPTS = CMSampleBufferGetPresentationTimeStamp(sample)
                    firstDuration = CMSampleBufferGetDuration(sample)
                }
                count += 1
            }
            return MP4SampleBufferTrackInfo(
                trackID: Int(track.trackID),
                kind: track.mediaType == .video ? .video : .audio,
                codec: codec(for: track),
                sampleCount: count,
                firstPresentationTime: firstPTS,
                firstDuration: firstDuration
            )
        }
    }

    private func codec(for track: AVAssetTrack) -> String {
        guard let rawDescription = track.formatDescriptions.first else { return "unknown" }
        let description = rawDescription as! CMFormatDescription
        let fourCC = CMFormatDescriptionGetMediaSubType(description)
        let bytes = [
            UInt8((fourCC >> 24) & 0xff),
            UInt8((fourCC >> 16) & 0xff),
            UInt8((fourCC >> 8) & 0xff),
            UInt8(fourCC & 0xff)
        ]
        return String(bytes: bytes, encoding: .macOSRoman)?.lowercased() ?? "unknown"
    }
}
