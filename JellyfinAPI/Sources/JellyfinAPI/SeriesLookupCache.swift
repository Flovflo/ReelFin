import Foundation
import Shared

/// Caches series lookups for episodes to avoid hammering the Jellyfin API
/// when resolving series displaying information on the Home rails.
public actor SeriesLookupCache {
    private let apiClient: any JellyfinAPIClientProtocol & Sendable
    private var cache: [String: MediaItem] = [:]
    private var inFlightContinuations: [String: [CheckedContinuation<MediaItem, Error>]] = [:]

    public init(apiClient: any JellyfinAPIClientProtocol & Sendable) {
        self.apiClient = apiClient
    }

    public func getSeries(id: String) async throws -> MediaItem {
        if let cached = cache[id] {
            return cached
        }

        if inFlightContinuations[id] != nil {
            return try await withCheckedThrowingContinuation { continuation in
                inFlightContinuations[id, default: []].append(continuation)
            }
        }

        inFlightContinuations[id] = []

        do {
            let item = try await apiClient.fetchItem(id: id)
            cache[id] = item
            let continuations = inFlightContinuations.removeValue(forKey: id) ?? []
            for continuation in continuations {
                continuation.resume(returning: item)
            }
            return item
        } catch {
            let continuations = inFlightContinuations.removeValue(forKey: id) ?? []
            for continuation in continuations {
                continuation.resume(throwing: error)
            }
            throw error
        }
    }

    public func clear() {
        cache.removeAll()
        inFlightContinuations.removeAll()
    }
}
