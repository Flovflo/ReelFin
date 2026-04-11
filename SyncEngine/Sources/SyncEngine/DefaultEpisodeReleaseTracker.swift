import Foundation
import Shared

public actor DefaultEpisodeReleaseTracker: EpisodeReleaseTrackingProtocol {
    private let apiClient: any JellyfinAPIClientProtocol & Sendable
    private let repository: any MetadataRepositoryProtocol & Sendable
    private let nextUpLimit: Int

    public init(
        apiClient: any JellyfinAPIClientProtocol & Sendable,
        repository: any MetadataRepositoryProtocol & Sendable,
        nextUpLimit: Int = 200
    ) {
        self.apiClient = apiClient
        self.repository = repository
        self.nextUpLimit = nextUpLimit
    }

    public func markSeriesFollowed(from episode: MediaItem) async {
        guard episode.mediaType == .episode, let seriesID = episode.parentID else { return }

        do {
            if var existing = try await repository.fetchEpisodeReleaseState(seriesID: seriesID) {
                existing.seriesName = preferredSeriesName(for: episode, fallback: existing.seriesName)
                existing.updatedAt = Date()
                try await repository.upsertEpisodeReleaseState(existing)
                return
            }

            let nextUp = try await resolveCurrentNextUpAfterPlayback(for: episode, seriesID: seriesID)
            let state = makeState(
                seriesID: seriesID,
                seriesName: preferredSeriesName(for: episode),
                nextUpEpisode: nextUp,
                lastNotifiedEpisodeID: nil
            )
            try await repository.upsertEpisodeReleaseState(state)
        } catch {
            AppLog.sync.warning(
                "Failed to mark series followed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    public func reconcileAfterSync(feed: HomeFeed) async -> [EpisodeReleaseAlert] {
        do {
            let nextUpEpisodes = try await apiClient.fetchNextUpEpisodes(limit: nextUpLimit)
            let nextUpBySeries = Dictionary(
                uniqueKeysWithValues: nextUpEpisodes.compactMap { episode -> (String, MediaItem)? in
                    guard let seriesID = episode.parentID else { return nil }
                    return (seriesID, episode)
                }
            )

            var statesBySeries = Dictionary(
                uniqueKeysWithValues: try await repository.fetchEpisodeReleaseStates().map { ($0.seriesID, $0) }
            )

            for (seriesID, nextUpEpisode) in nextUpBySeries where statesBySeries[seriesID] == nil {
                let seededState = makeState(
                    seriesID: seriesID,
                    seriesName: preferredSeriesName(for: nextUpEpisode),
                    nextUpEpisode: nextUpEpisode,
                    lastNotifiedEpisodeID: nil
                )
                statesBySeries[seriesID] = seededState
                try await repository.upsertEpisodeReleaseState(seededState)
            }

            for episode in continueWatchingEpisodes(from: feed) {
                guard let seriesID = episode.parentID, statesBySeries[seriesID] == nil else { continue }

                let seededState = makeState(
                    seriesID: seriesID,
                    seriesName: preferredSeriesName(for: episode),
                    nextUpEpisode: nextUpBySeries[seriesID],
                    lastNotifiedEpisodeID: nil
                )
                statesBySeries[seriesID] = seededState
                try await repository.upsertEpisodeReleaseState(seededState)
            }

            var alerts: [EpisodeReleaseAlert] = []
            alerts.reserveCapacity(statesBySeries.count)

            for (seriesID, currentState) in statesBySeries {
                var updatedState = currentState
                let nextUpEpisode = nextUpBySeries[seriesID]

                if
                    updatedState.lastKnownNextUpEpisodeID == nil,
                    let nextUpEpisode,
                    updatedState.lastNotifiedEpisodeID != nextUpEpisode.id
                {
                    alerts.append(
                        EpisodeReleaseAlert(
                            seriesID: seriesID,
                            seriesName: preferredSeriesName(for: nextUpEpisode, fallback: updatedState.seriesName),
                            episodeID: nextUpEpisode.id,
                            episodeTitle: nextUpEpisode.name,
                            seasonNumber: nextUpEpisode.parentIndexNumber,
                            episodeNumber: nextUpEpisode.indexNumber
                        )
                    )
                    updatedState.lastNotifiedEpisodeID = nextUpEpisode.id
                }

                updatedState.seriesName = nextUpEpisode.map { preferredSeriesName(for: $0, fallback: updatedState.seriesName) }
                    ?? updatedState.seriesName
                updatedState.lastKnownNextUpEpisodeID = nextUpEpisode?.id
                updatedState.lastKnownNextUpSeasonNumber = nextUpEpisode?.parentIndexNumber
                updatedState.lastKnownNextUpEpisodeNumber = nextUpEpisode?.indexNumber
                updatedState.updatedAt = Date()

                try await repository.upsertEpisodeReleaseState(updatedState)
            }

            return alerts
        } catch {
            AppLog.sync.warning(
                "Episode release reconciliation failed: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    private func continueWatchingEpisodes(from feed: HomeFeed) -> [MediaItem] {
        guard let row = feed.rows.first(where: { $0.kind == .continueWatching }) else {
            return []
        }

        return row.items.filter { $0.mediaType == .episode && $0.parentID != nil }
    }

    private func makeState(
        seriesID: String,
        seriesName: String,
        nextUpEpisode: MediaItem?,
        lastNotifiedEpisodeID: String?
    ) -> EpisodeReleaseState {
        EpisodeReleaseState(
            seriesID: seriesID,
            seriesName: seriesName,
            lastKnownNextUpEpisodeID: nextUpEpisode?.id,
            lastKnownNextUpSeasonNumber: nextUpEpisode?.parentIndexNumber,
            lastKnownNextUpEpisodeNumber: nextUpEpisode?.indexNumber,
            lastNotifiedEpisodeID: lastNotifiedEpisodeID,
            updatedAt: Date()
        )
    }

    private func preferredSeriesName(for episode: MediaItem, fallback: String? = nil) -> String {
        episode.seriesName ?? fallback ?? episode.name
    }

    private func resolveCurrentNextUpAfterPlayback(for episode: MediaItem, seriesID: String) async throws -> MediaItem? {
        let firstAttempt = try await apiClient.fetchNextUpEpisode(seriesID: seriesID)
        guard firstAttempt?.id == episode.id else {
            return firstAttempt
        }

        try? await Task.sleep(nanoseconds: 400_000_000)
        return try await apiClient.fetchNextUpEpisode(seriesID: seriesID)
    }
}
