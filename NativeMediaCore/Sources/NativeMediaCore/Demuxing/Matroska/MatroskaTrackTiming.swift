import CoreMedia
import Foundation

public enum MatroskaTrackTiming {
    public static func defaultDurations(for tracks: [MatroskaParsedTrack]) -> [Int: CMTime] {
        Dictionary(
            uniqueKeysWithValues: tracks.compactMap { track -> (Int, CMTime)? in
                guard let duration = defaultDuration(for: track) else { return nil }
                return (track.number, duration)
            }
        )
    }

    public static func defaultDuration(for track: MatroskaParsedTrack) -> CMTime? {
        if let defaultDuration = track.defaultDuration, defaultDuration > 0 {
            return CMTime(value: Int64(defaultDuration), timescale: 1_000_000_000)
        }
        guard track.type == .audio else { return nil }
        guard let frames = audioFramesPerPacket(codec: track.codec) else { return nil }
        guard let sampleRate = track.audio?.sampleRate ?? defaultSampleRate(codec: track.codec), sampleRate > 0 else {
            return nil
        }
        return CMTime(value: Int64(frames), timescale: CMTimeScale(sampleRate.rounded()))
    }

    private static func audioFramesPerPacket(codec: String) -> Int? {
        switch codec.lowercased() {
        case "aac", "alac":
            return 1024
        case "ac3", "eac3":
            return 1536
        case "mp3":
            return 1152
        case "opus":
            return 960
        default:
            return nil
        }
    }

    private static func defaultSampleRate(codec: String) -> Double? {
        switch codec.lowercased() {
        case "opus":
            return 48_000
        default:
            return nil
        }
    }
}
