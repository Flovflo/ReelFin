import Shared

enum EpisodePlaybackQueueResolver {
    static func loadFollowingEpisodes(
        after currentEpisode: MediaItem,
        repository: any MediaDetailRepositoryProtocol
    ) async -> [MediaItem] {
        guard currentEpisode.mediaType == .episode,
              let seriesID = currentEpisode.parentID else {
            return []
        }

        do {
            let seasons = orderedSeasons(
                try await repository.loadSeasons(seriesID: seriesID)
            )
            var episodesBySeasonID: [String: [MediaItem]] = [:]

            let currentSeasonIndex: Int?
            if let seasonNumber = currentEpisode.parentIndexNumber {
                currentSeasonIndex = seasons.firstIndex { $0.indexNumber == seasonNumber }
            } else {
                currentSeasonIndex = nil
            }

            if let currentSeasonIndex {
                let currentSeason = seasons[currentSeasonIndex]
                episodesBySeasonID[currentSeason.id] = try await repository.loadEpisodes(
                    seriesID: seriesID,
                    seasonID: currentSeason.id
                )

                let currentSeasonQueue = followingEpisodes(
                    after: currentEpisode,
                    seasons: seasons,
                    episodesBySeasonID: episodesBySeasonID
                )
                if !currentSeasonQueue.isEmpty {
                    return currentSeasonQueue
                }

                var nextSeasonIndex = seasons.index(after: currentSeasonIndex)
                while nextSeasonIndex < seasons.endIndex {
                    guard !Task.isCancelled else { return [] }
                    let nextSeason = seasons[nextSeasonIndex]
                    episodesBySeasonID[nextSeason.id] = try await repository.loadEpisodes(
                        seriesID: seriesID,
                        seasonID: nextSeason.id
                    )

                    let nextSeasonQueue = followingEpisodes(
                        after: currentEpisode,
                        seasons: seasons,
                        episodesBySeasonID: episodesBySeasonID
                    )
                    if !nextSeasonQueue.isEmpty {
                        return nextSeasonQueue
                    }
                    nextSeasonIndex = seasons.index(after: nextSeasonIndex)
                }
            } else {
                // Older Jellyfin payloads can omit ParentIndexNumber. Probe in server order until
                // the owning season is found, then stop as soon as a following episode exists.
                for season in seasons {
                    guard !Task.isCancelled else { return [] }
                    episodesBySeasonID[season.id] = try await repository.loadEpisodes(
                        seriesID: seriesID,
                        seasonID: season.id
                    )
                    let queue = followingEpisodes(
                        after: currentEpisode,
                        seasons: seasons,
                        episodesBySeasonID: episodesBySeasonID
                    )
                    if !queue.isEmpty { return queue }
                }
            }

            guard !Task.isCancelled else { return [] }
            return followingEpisodes(
                after: currentEpisode,
                seasons: seasons,
                episodesBySeasonID: episodesBySeasonID
            )
        } catch {
            return []
        }
    }

    static func followingEpisodes(
        after currentEpisode: MediaItem,
        seasons: [MediaItem],
        episodesBySeasonID: [String: [MediaItem]]
    ) -> [MediaItem] {
        var seenIDs = Set<String>()
        var seenCoordinates = Set<EpisodeCoordinate>()
        var orderedEpisodes: [MediaItem] = []

        for season in orderedSeasons(seasons) {
            for episode in episodesBySeasonID[season.id] ?? [] {
                guard episode.mediaType == .episode else { continue }
                guard seenIDs.insert(episode.id).inserted else { continue }

                if let seasonNumber = episode.parentIndexNumber,
                   let episodeNumber = episode.indexNumber,
                   !seenCoordinates.insert(
                       EpisodeCoordinate(season: seasonNumber, episode: episodeNumber)
                   ).inserted {
                    continue
                }

                orderedEpisodes.append(episode)
            }
        }

        guard let currentIndex = orderedEpisodes.firstIndex(where: { $0.id == currentEpisode.id }) else {
            return []
        }
        let nextIndex = orderedEpisodes.index(after: currentIndex)
        guard nextIndex < orderedEpisodes.endIndex else { return [] }
        return Array(orderedEpisodes[nextIndex...])
    }

    private struct EpisodeCoordinate: Hashable {
        let season: Int
        let episode: Int
    }

    private static func orderedSeasons(_ seasons: [MediaItem]) -> [MediaItem] {
        seasons.enumerated().sorted { lhs, rhs in
            switch (lhs.element.indexNumber, rhs.element.indexNumber) {
            case let (left?, right?) where left != right:
                return left < right
            default:
                return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }
}
