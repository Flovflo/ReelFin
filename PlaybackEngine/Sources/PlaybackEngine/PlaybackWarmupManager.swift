import Foundation
import Shared

public protocol PlaybackWarmupManaging: AnyObject, Sendable {
    func warm(itemID: String) async
    func selection(for itemID: String) async -> PlaybackAssetSelection?
    func cancel(itemID: String) async
    func trim(keeping itemIDs: [String]) async
    func invalidate(itemID: String) async
}

public actor PlaybackWarmupManager: PlaybackWarmupManaging {
    private struct WarmEntry: Sendable {
        let selection: PlaybackAssetSelection
        let expirationDate: Date
        let lastAccessDate: Date

        func isValid(at date: Date) -> Bool {
            expirationDate > date
        }
    }

    private let ttl: TimeInterval
    private let resolver: @Sendable (String) async throws -> PlaybackAssetSelection

    private var cache: [String: WarmEntry] = [:]
    private var inFlight: [String: Task<PlaybackAssetSelection, Error>] = [:]

    public init(
        ttl: TimeInterval = 240,
        resolver: @escaping @Sendable (String) async throws -> PlaybackAssetSelection
    ) {
        self.ttl = ttl
        self.resolver = resolver
    }

    public init(
        apiClient: any JellyfinAPIClientProtocol & Sendable,
        ttl: TimeInterval = 240,
        decisionEngine: PlaybackDecisionEngine = PlaybackDecisionEngine()
    ) {
        let coordinator = PlaybackCoordinator(apiClient: apiClient, decisionEngine: decisionEngine)
        self.ttl = ttl
        self.resolver = { itemID in
            try await coordinator.resolvePlayback(
                itemID: itemID,
                mode: .balanced,
                allowTranscodingFallbackInPerformance: true
            )
        }
    }

    public func warm(itemID: String) async {
        _ = try? await resolveWarmSelection(itemID: itemID)
    }

    public func selection(for itemID: String) async -> PlaybackAssetSelection? {
        let now = Date()
        if let entry = cache[itemID], entry.isValid(at: now) {
            cache[itemID] = WarmEntry(
                selection: entry.selection,
                expirationDate: entry.expirationDate,
                lastAccessDate: now
            )
            return entry.selection
        }
        if let task = inFlight[itemID] {
            return try? await task.value
        }
        cache[itemID] = nil
        return nil
    }

    public func cancel(itemID: String) async {
        inFlight[itemID]?.cancel()
        inFlight[itemID] = nil
    }

    public func trim(keeping itemIDs: [String]) async {
        var keep = Set(itemIDs)

        let recentKeys = cache
            .sorted { lhs, rhs in lhs.value.lastAccessDate > rhs.value.lastAccessDate }
            .prefix(4)
            .map(\.key)
        keep.formUnion(recentKeys)

        for key in inFlight.keys where !keep.contains(key) {
            inFlight[key]?.cancel()
            inFlight[key] = nil
        }

        cache = cache.filter { keep.contains($0.key) }
    }

    public func invalidate(itemID: String) async {
        cache[itemID] = nil
        inFlight[itemID]?.cancel()
        inFlight[itemID] = nil
    }

    private func resolveWarmSelection(itemID: String) async throws -> PlaybackAssetSelection {
        let now = Date()
        if let entry = cache[itemID], entry.isValid(at: now) {
            return entry.selection
        }

        if let task = inFlight[itemID] {
            return try await task.value
        }

        let task = Task<PlaybackAssetSelection, Error> {
            try await resolver(itemID)
        }
        inFlight[itemID] = task

        do {
            let selection = try await task.value
            cache[itemID] = WarmEntry(
                selection: selection,
                expirationDate: now.addingTimeInterval(ttl),
                lastAccessDate: now
            )
            inFlight[itemID] = nil
            return selection
        } catch {
            inFlight[itemID] = nil
            throw error
        }
    }
}
