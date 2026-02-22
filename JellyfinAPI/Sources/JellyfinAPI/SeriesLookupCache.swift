import Foundation
import Shared

/// Caches series lookups for episodes to avoid hammering the Jellyfin API
/// when resolving series displaying information on the Home rails.
public actor SeriesLookupCache {
    private let apiClient: JellyfinAPIClientProtocol
    private var cache: [String: MediaItem] = [:]
    private var inFlightTasks: [String: Task<MediaItem, Error>] = [:]

    public init(apiClient: JellyfinAPIClientProtocol) {
        self.apiClient = apiClient
    }

    public func getSeries(id: String) async throws -> MediaItem {
        if let cached = cache[id] {
            return cached
        }

        if let inFlight = inFlightTasks[id] {
            return try await inFlight.value
        }

        let task = Task<MediaItem, Error> {
            let item = try await apiClient.fetchItem(id: id)
            return item
        }

        inFlightTasks[id] = task

        do {
            let item = try await task.value
            cache[id] = item
            inFlightTasks[id] = nil
            return item
        } catch {
            inFlightTasks[id] = nil
            throw error
        }
    }

    public func clear() {
        cache.removeAll()
        inFlightTasks.removeAll()
    }
}
