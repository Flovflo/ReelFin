import Foundation
import Shared

extension PlaybackSessionController {
    func refreshPlaybackMarkers(for item: MediaItem) async {
        let segments = (try? await apiClient.fetchMediaSegments(itemID: item.id)) ?? []
        guard currentItemID == item.id, currentMediaItem?.id == item.id else { return }

        mediaSegments = segments
            .filter(\.isValid)
            .sorted { lhs, rhs in
                if lhs.startTicks != rhs.startTicks {
                    return lhs.startTicks < rhs.startTicks
                }
                return lhs.type.rawValue < rhs.type.rawValue
            }

        updateActiveSkipSuggestion()
    }

    public func skipCurrentSegment() {
        guard let suggestion = activeSkipSuggestion else { return }

        switch suggestion.target {
        case let .seek(to: targetSeconds):
            currentTime = targetSeconds
            seek(to: targetSeconds)
            updateActiveSkipSuggestion()
        case .nextEpisode:
            Task { @MainActor [weak self] in
                _ = await self?.playNextEpisode()
            }
        }
    }

    func updateActiveSkipSuggestion() {
        activeSkipSuggestion = PlaybackSkipSuggestionResolver.suggestion(
            segments: mediaSegments,
            currentTime: currentTime,
            duration: duration,
            currentItem: currentMediaItem,
            nextEpisodeQueue: nextEpisodeQueue
        )
    }

    func playNextEpisode() async -> Bool {
        guard currentMediaItem?.mediaType == .episode,
              let nextEpisode = nextEpisodeQueue.first else {
            return false
        }

        let remainingQueue = Array(nextEpisodeQueue.dropFirst())

        await finishCurrentPlayback()

        do {
            try await load(item: nextEpisode, autoPlay: true, upNextEpisodes: remainingQueue)
            return true
        } catch {
            playbackErrorMessage = error.localizedDescription
            return false
        }
    }
}
