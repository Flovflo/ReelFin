import Foundation
import Shared

struct HybridSourceSelector {
    func analysisSource(from sources: [MediaSource]) -> MediaSource? {
        sources.max(by: { analysisScore(for: $0) < analysisScore(for: $1) })
    }

    func playbackSource(
        for engine: PlaybackEngineType,
        from sources: [MediaSource],
        preferred preferredSource: MediaSource?
    ) -> MediaSource? {
        let rankedSources = sources.sorted { playbackScore(for: $0, engine: engine) > playbackScore(for: $1, engine: engine) }
        if let preferredSource,
           rankedSources.contains(where: { $0.id == preferredSource.id }) {
            return rankedSources.first(where: { $0.id == preferredSource.id && playbackScore(for: $0, engine: engine) > 0 })
                ?? rankedSources.first(where: { playbackScore(for: $0, engine: engine) > 0 })
        }
        return rankedSources.first(where: { playbackScore(for: $0, engine: engine) > 0 })
    }

    private func analysisScore(for source: MediaSource) -> Int {
        var score = 0
        if source.supportsDirectPlay { score += 120 }
        if source.supportsDirectStream { score += 100 }
        if source.directPlayURL != nil { score += 60 }
        if source.directStreamURL != nil { score += 50 }
        if source.transcodeURL != nil { score += 10 }
        if !(source.normalizedContainer.isEmpty) { score += 12 }
        if !(source.normalizedVideoCodec.isEmpty) { score += 12 }
        if !(source.normalizedAudioCodec.isEmpty) { score += 8 }
        if !source.subtitleTracks.isEmpty { score += 4 }
        return score
    }

    private func playbackScore(for source: MediaSource, engine: PlaybackEngineType) -> Int {
        switch engine {
        case .native:
            var score = 0
            if source.supportsDirectPlay && source.directPlayURL != nil { score += 200 }
            return score
        case .vlc:
            var score = 0
            if source.directPlayURL != nil { score += 120 }
            if source.directStreamURL != nil { score += 100 }
            if source.supportsDirectPlay { score += 40 }
            if source.supportsDirectStream { score += 30 }
            if source.transcodeURL != nil { score += 10 }
            return score
        }
    }
}
