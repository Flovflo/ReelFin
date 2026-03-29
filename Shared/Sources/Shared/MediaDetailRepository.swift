import Foundation

public actor DefaultMediaDetailRepository: MediaDetailRepositoryProtocol {
    private struct TimedValue<Value: Sendable>: Sendable {
        let value: Value
        let expirationDate: Date

        func isValid(at date: Date) -> Bool {
            expirationDate > date
        }
    }

    private let apiClient: any JellyfinAPIClientProtocol
    private let repository: any MetadataRepositoryProtocol
    private let itemTTL: TimeInterval
    private let detailTTL: TimeInterval
    private let collectionTTL: TimeInterval

    private var itemCache: [String: TimedValue<MediaItem>] = [:]
    private var detailCache: [String: TimedValue<MediaDetail>] = [:]
    private var seasonsCache: [String: TimedValue<[MediaItem]>] = [:]
    private var episodesCache: [String: TimedValue<[MediaItem]>] = [:]
    private var nextUpCache: [String: TimedValue<MediaItem?>] = [:]

    private var itemTasks: [String: Task<MediaItem, Error>] = [:]
    private var detailTasks: [String: Task<MediaDetail, Error>] = [:]
    private var seasonsTasks: [String: Task<[MediaItem], Error>] = [:]
    private var episodesTasks: [String: Task<[MediaItem], Error>] = [:]
    private var nextUpTasks: [String: Task<MediaItem?, Error>] = [:]

    public init(
        apiClient: any JellyfinAPIClientProtocol,
        repository: any MetadataRepositoryProtocol,
        itemTTL: TimeInterval = 10 * 60,
        detailTTL: TimeInterval = 5 * 60,
        collectionTTL: TimeInterval = 5 * 60
    ) {
        self.apiClient = apiClient
        self.repository = repository
        self.itemTTL = itemTTL
        self.detailTTL = detailTTL
        self.collectionTTL = collectionTTL
    }

    public func cachedItem(id: String) async -> MediaItem? {
        let now = Date()
        if let cached = itemCache[id], cached.isValid(at: now) {
            return cached.value
        }

        if let stored = try? await repository.fetchItem(id: id) {
            itemCache[id] = TimedValue(value: stored, expirationDate: expirationDate(ttl: itemTTL, from: now))
            return stored
        }

        return nil
    }

    public func refreshItem(id: String) async throws -> MediaItem {
        let task = existingItemTask(for: id) ?? makeItemTask(for: id)
        let item = try await task.value
        itemTasks[id] = nil
        return item
    }

    public func loadDetail(id: String) async throws -> MediaDetail {
        let now = Date()
        if let cached = detailCache[id], cached.isValid(at: now) {
            return cached.value
        }

        let task = existingDetailTask(for: id) ?? makeDetailTask(for: id)
        let detail = try await task.value
        detailTasks[id] = nil
        return detail
    }

    public func loadSeasons(seriesID: String) async throws -> [MediaItem] {
        let now = Date()
        if let cached = seasonsCache[seriesID], cached.isValid(at: now) {
            return cached.value
        }

        let task = existingSeasonsTask(for: seriesID) ?? makeSeasonsTask(for: seriesID)
        let seasons = try await task.value
        seasonsTasks[seriesID] = nil
        return seasons
    }

    public func loadEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] {
        let key = episodesKey(seriesID: seriesID, seasonID: seasonID)
        let now = Date()
        if let cached = episodesCache[key], cached.isValid(at: now) {
            return cached.value
        }

        let task = existingEpisodesTask(for: key) ?? makeEpisodesTask(seriesID: seriesID, seasonID: seasonID, cacheKey: key)
        let episodes = try await task.value
        episodesTasks[key] = nil
        return episodes
    }

    public func loadNextUpEpisode(seriesID: String) async throws -> MediaItem? {
        let now = Date()
        if let cached = nextUpCache[seriesID], cached.isValid(at: now) {
            return cached.value
        }

        let task = existingNextUpTask(for: seriesID) ?? makeNextUpTask(for: seriesID)
        let nextUpEpisode = try await task.value
        nextUpTasks[seriesID] = nil
        return nextUpEpisode
    }

    public func primeItem(id: String) async {
        _ = try? await refreshItem(id: id)
    }

    public func primeDetail(id: String) async {
        _ = try? await loadDetail(id: id)
    }

    private func makeItemTask(for id: String) -> Task<MediaItem, Error> {
        let repository = repository
        let apiClient = apiClient
        let ttl = itemTTL

        let task = Task<MediaItem, Error> {
            let item = try await apiClient.fetchItem(id: id)
            try? await repository.upsertItems([item])
            return item
        }

        itemTasks[id] = task

        Task {
            if let item = try? await task.value {
                self.store(item: item, ttl: ttl)
            }
        }

        return task
    }

    private func makeDetailTask(for id: String) -> Task<MediaDetail, Error> {
        let repository = repository
        let apiClient = apiClient
        let ttl = detailTTL
        let itemTTL = itemTTL

        let task = Task<MediaDetail, Error> {
            let detail = try await apiClient.fetchItemDetail(id: id)
            try? await repository.upsertItems([detail.item] + detail.similar)
            return detail
        }

        detailTasks[id] = task

        Task {
            if let detail = try? await task.value {
                self.store(detail: detail, detailTTL: ttl, itemTTL: itemTTL)
            }
        }

        return task
    }

    private func makeSeasonsTask(for seriesID: String) -> Task<[MediaItem], Error> {
        let repository = repository
        let apiClient = apiClient
        let ttl = collectionTTL

        let task = Task<[MediaItem], Error> {
            let seasons = try await apiClient.fetchSeasons(seriesID: seriesID)
            try? await repository.upsertItems(seasons)
            return seasons
        }

        seasonsTasks[seriesID] = task

        Task {
            if let seasons = try? await task.value {
                self.store(seasons: seasons, for: seriesID, ttl: ttl)
            }
        }

        return task
    }

    private func makeEpisodesTask(seriesID: String, seasonID: String, cacheKey: String) -> Task<[MediaItem], Error> {
        let repository = repository
        let apiClient = apiClient
        let ttl = collectionTTL

        let task = Task<[MediaItem], Error> {
            let episodes = try await apiClient.fetchEpisodes(seriesID: seriesID, seasonID: seasonID)
            try? await repository.upsertItems(episodes)
            return episodes
        }

        episodesTasks[cacheKey] = task

        Task {
            if let episodes = try? await task.value {
                self.store(episodes: episodes, key: cacheKey, ttl: ttl)
            }
        }

        return task
    }

    private func makeNextUpTask(for seriesID: String) -> Task<MediaItem?, Error> {
        let repository = repository
        let apiClient = apiClient
        let ttl = collectionTTL

        let task = Task<MediaItem?, Error> {
            let episode = try await apiClient.fetchNextUpEpisode(seriesID: seriesID)
            if let episode {
                try? await repository.upsertItems([episode])
            }
            return episode
        }

        nextUpTasks[seriesID] = task

        Task {
            if let episode = try? await task.value {
                self.store(nextUpEpisode: episode, for: seriesID, ttl: ttl)
            }
        }

        return task
    }

    private func existingItemTask(for id: String) -> Task<MediaItem, Error>? {
        itemTasks[id]
    }

    private func existingDetailTask(for id: String) -> Task<MediaDetail, Error>? {
        detailTasks[id]
    }

    private func existingSeasonsTask(for seriesID: String) -> Task<[MediaItem], Error>? {
        seasonsTasks[seriesID]
    }

    private func existingEpisodesTask(for key: String) -> Task<[MediaItem], Error>? {
        episodesTasks[key]
    }

    private func existingNextUpTask(for seriesID: String) -> Task<MediaItem?, Error>? {
        nextUpTasks[seriesID]
    }

    private func store(item: MediaItem, ttl: TimeInterval) {
        itemCache[item.id] = TimedValue(value: item, expirationDate: expirationDate(ttl: ttl, from: Date()))
    }

    private func store(detail: MediaDetail, detailTTL: TimeInterval, itemTTL: TimeInterval) {
        let now = Date()
        detailCache[detail.item.id] = TimedValue(value: detail, expirationDate: expirationDate(ttl: detailTTL, from: now))
        itemCache[detail.item.id] = TimedValue(value: detail.item, expirationDate: expirationDate(ttl: itemTTL, from: now))
        for item in detail.similar {
            itemCache[item.id] = TimedValue(value: item, expirationDate: expirationDate(ttl: itemTTL, from: now))
        }
    }

    private func store(seasons: [MediaItem], for seriesID: String, ttl: TimeInterval) {
        seasonsCache[seriesID] = TimedValue(value: seasons, expirationDate: expirationDate(ttl: ttl, from: Date()))
    }

    private func store(episodes: [MediaItem], key: String, ttl: TimeInterval) {
        episodesCache[key] = TimedValue(value: episodes, expirationDate: expirationDate(ttl: ttl, from: Date()))
    }

    private func store(nextUpEpisode: MediaItem?, for seriesID: String, ttl: TimeInterval) {
        nextUpCache[seriesID] = TimedValue(value: nextUpEpisode, expirationDate: expirationDate(ttl: ttl, from: Date()))
    }

    private func episodesKey(seriesID: String, seasonID: String) -> String {
        "\(seriesID)::\(seasonID)"
    }

    private func expirationDate(ttl: TimeInterval, from date: Date) -> Date {
        date.addingTimeInterval(ttl)
    }
}
