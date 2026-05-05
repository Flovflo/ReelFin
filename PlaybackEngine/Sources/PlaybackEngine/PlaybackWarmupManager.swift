import Foundation
import Shared

public protocol PlaybackWarmupManaging: AnyObject, Sendable {
    func warm(itemID: String) async
    func warm(itemID: String, resumeSeconds: Double, runtimeSeconds: Double?, isTVOS: Bool) async
    func warm(
        selection: PlaybackAssetSelection,
        resumeSeconds: Double,
        runtimeSeconds: Double?,
        isTVOS: Bool
    ) async -> PlaybackStartupPreheater.Result?
    func selection(for itemID: String) async -> PlaybackAssetSelection?
    func startupPreheatResult(
        for itemID: String,
        resumeSeconds: Double,
        runtimeSeconds: Double?,
        isTVOS: Bool
    ) async -> PlaybackStartupPreheater.Result?
    func startupPreheatResult(
        for selection: PlaybackAssetSelection,
        resumeSeconds: Double,
        runtimeSeconds: Double?,
        isTVOS: Bool
    ) async -> PlaybackStartupPreheater.Result?
    func warmServerBaselineIfNeeded(
        selection: PlaybackAssetSelection,
        isTVOS: Bool
    ) async -> PlaybackServerNetworkBaseline.Result?
    func serverBaselineResult(
        for selection: PlaybackAssetSelection,
        isTVOS: Bool
    ) async -> PlaybackServerNetworkBaseline.Result?
    func cancel(itemID: String) async
    func trim(keeping itemIDs: [String]) async
    func invalidate(itemID: String) async
}

public extension PlaybackWarmupManaging {
    func warm(itemID: String, resumeSeconds: Double, runtimeSeconds: Double?, isTVOS: Bool) async {
        _ = resumeSeconds
        _ = runtimeSeconds
        _ = isTVOS
        await warm(itemID: itemID)
    }

    func warm(
        selection: PlaybackAssetSelection,
        resumeSeconds: Double,
        runtimeSeconds: Double?,
        isTVOS: Bool
    ) async -> PlaybackStartupPreheater.Result? {
        _ = selection
        _ = resumeSeconds
        _ = runtimeSeconds
        _ = isTVOS
        return nil
    }

    func startupPreheatResult(
        for itemID: String,
        resumeSeconds: Double,
        runtimeSeconds: Double?,
        isTVOS: Bool
    ) async -> PlaybackStartupPreheater.Result? {
        _ = itemID
        _ = resumeSeconds
        _ = runtimeSeconds
        _ = isTVOS
        return nil
    }

    func startupPreheatResult(
        for selection: PlaybackAssetSelection,
        resumeSeconds: Double,
        runtimeSeconds: Double?,
        isTVOS: Bool
    ) async -> PlaybackStartupPreheater.Result? {
        _ = selection
        _ = resumeSeconds
        _ = runtimeSeconds
        _ = isTVOS
        return nil
    }

    func warmServerBaselineIfNeeded(
        selection: PlaybackAssetSelection,
        isTVOS: Bool
    ) async -> PlaybackServerNetworkBaseline.Result? {
        _ = selection
        _ = isTVOS
        return nil
    }

    func serverBaselineResult(
        for selection: PlaybackAssetSelection,
        isTVOS: Bool
    ) async -> PlaybackServerNetworkBaseline.Result? {
        _ = selection
        _ = isTVOS
        return nil
    }
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

    private struct StartupPreheatEntry: Sendable {
        let result: PlaybackStartupPreheater.Result
        let expirationDate: Date

        func isValid(at date: Date) -> Bool {
            expirationDate > date
        }
    }

    private struct StartupPreheatKey: Hashable, Sendable {
        let itemID: String
        let sourceID: String
        let routeSignature: String
        let routeKind: String
        let resumeBucket: Int
        let isTVOS: Bool
    }

    private struct ServerBaselineEntry: Sendable {
        let result: PlaybackServerNetworkBaseline.Result
        let expirationDate: Date

        func isValid(at date: Date) -> Bool {
            expirationDate > date
        }
    }

    private struct ServerBaselineKey: Hashable, Sendable {
        let serverKey: String
        let networkScope: String
        let isTVOS: Bool
    }

    private let ttl: TimeInterval
    private let resolver: @Sendable (String) async throws -> PlaybackAssetSelection
    private let startupPreheater: @Sendable (
        PlaybackAssetSelection,
        Double,
        Double?,
        Bool
    ) async -> PlaybackStartupPreheater.Result?
    private let serverBaselineWarmer: @Sendable (
        PlaybackAssetSelection,
        Bool
    ) async -> PlaybackServerNetworkBaseline.Result?

    private var cache: [String: WarmEntry] = [:]
    private var inFlight: [String: Task<PlaybackAssetSelection, Error>] = [:]
    private var startupPreheatCache: [StartupPreheatKey: StartupPreheatEntry] = [:]
    private var startupPreheatInFlight: [StartupPreheatKey: Task<PlaybackStartupPreheater.Result?, Never>] = [:]
    private var serverBaselineCache: [ServerBaselineKey: ServerBaselineEntry] = [:]
    private var serverBaselineInFlight: [ServerBaselineKey: Task<PlaybackServerNetworkBaseline.Result?, Never>] = [:]

    public init(
        ttl: TimeInterval = 240,
        resolver: @escaping @Sendable (String) async throws -> PlaybackAssetSelection
    ) {
        self.init(
            ttl: ttl,
            resolver: resolver,
            startupPreheater: Self.makeDefaultStartupPreheater(),
            serverBaselineWarmer: Self.makeDefaultServerBaselineWarmer()
        )
    }

    public init(
        ttl: TimeInterval = 240,
        resolver: @escaping @Sendable (String) async throws -> PlaybackAssetSelection,
        startupPreheater: @escaping @Sendable (
            PlaybackAssetSelection,
            Double,
            Double?,
            Bool
        ) async -> PlaybackStartupPreheater.Result?
    ) {
        self.init(
            ttl: ttl,
            resolver: resolver,
            startupPreheater: startupPreheater,
            serverBaselineWarmer: Self.makeDefaultServerBaselineWarmer()
        )
    }

    public init(
        ttl: TimeInterval = 240,
        resolver: @escaping @Sendable (String) async throws -> PlaybackAssetSelection,
        startupPreheater: @escaping @Sendable (
            PlaybackAssetSelection,
            Double,
            Double?,
            Bool
        ) async -> PlaybackStartupPreheater.Result?,
        serverBaselineWarmer: @escaping @Sendable (
            PlaybackAssetSelection,
            Bool
        ) async -> PlaybackServerNetworkBaseline.Result?
    ) {
        self.ttl = ttl
        self.resolver = resolver
        self.startupPreheater = startupPreheater
        self.serverBaselineWarmer = serverBaselineWarmer
    }

    public init(
        apiClient: any JellyfinAPIClientProtocol & Sendable,
        ttl: TimeInterval = 240,
        decisionEngine: PlaybackDecisionEngine = PlaybackDecisionEngine()
    ) {
        let coordinator = PlaybackCoordinator(apiClient: apiClient, decisionEngine: decisionEngine)
        self.ttl = ttl
        self.resolver = { itemID in
            if let configuration = await apiClient.currentConfiguration() {
                let nativeConfig = configuration.nativePlayerConfig.applyingRuntimeOverride()
                if nativeConfig.enabled,
                   nativeConfig.surfacePreference == .directPlayWhenPossible {
                    guard let session = await apiClient.currentSession() else {
                        throw AppError.unauthenticated
                    }
                    let options = NativePlayerPlaybackController.originalPlaybackInfoOptions(
                        nativeConfig: nativeConfig,
                        startTimeTicks: nil
                    )
                    let sources = try await apiClient.fetchPlaybackSources(itemID: itemID, options: options)
                    let resolution = try OriginalMediaResolver().resolve(
                        request: OriginalMediaRequest(itemID: itemID),
                        sources: sources,
                        configuration: configuration,
                        session: session,
                        nativeConfig: nativeConfig
                    )
                    if let violation = NativePlayerRouteGuard.validateOriginalPlaybackURL(resolution.url).first {
                        throw violation
                    }
                    return NativePlayerPlaybackController.makeAppleNativeSelection(
                        resolution: resolution,
                        session: session
                    )
                }
            }
            return try await coordinator.resolvePlayback(
                itemID: itemID,
                mode: .balanced,
                allowTranscodingFallbackInPerformance: true
            )
        }
        self.startupPreheater = Self.makeDefaultStartupPreheater()
        self.serverBaselineWarmer = Self.makeDefaultServerBaselineWarmer()
    }

    public func warm(itemID: String) async {
        _ = try? await resolveWarmSelection(itemID: itemID)
    }

    public func warm(itemID: String, resumeSeconds: Double, runtimeSeconds: Double?, isTVOS: Bool) async {
        guard let selection = try? await resolveWarmSelection(itemID: itemID) else {
            return
        }

        _ = await warm(
            selection: selection,
            resumeSeconds: resumeSeconds,
            runtimeSeconds: runtimeSeconds,
            isTVOS: isTVOS
        )
    }

    public func warm(
        selection: PlaybackAssetSelection,
        resumeSeconds: Double,
        runtimeSeconds: Double?,
        isTVOS: Bool
    ) async -> PlaybackStartupPreheater.Result? {
        guard shouldAttemptStartupPreheat(
            selection: selection,
            resumeSeconds: resumeSeconds,
            runtimeSeconds: runtimeSeconds,
            isTVOS: isTVOS
        ) else {
            return nil
        }

        guard let key = startupPreheatKey(
            for: selection,
            resumeSeconds: resumeSeconds,
            isTVOS: isTVOS
        ) else {
            return nil
        }

        return await resolveStartupPreheat(
            key: key,
            selection: selection,
            resumeSeconds: resumeSeconds,
            runtimeSeconds: runtimeSeconds,
            isTVOS: isTVOS
        )
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

    public func startupPreheatResult(
        for itemID: String,
        resumeSeconds: Double,
        runtimeSeconds: Double?,
        isTVOS: Bool
    ) async -> PlaybackStartupPreheater.Result? {
        guard let selection = await selection(for: itemID) else {
            return nil
        }

        guard shouldAttemptStartupPreheat(
            selection: selection,
            resumeSeconds: resumeSeconds,
            runtimeSeconds: runtimeSeconds,
            isTVOS: isTVOS
        ) else {
            return nil
        }

        guard let key = startupPreheatKey(
            for: selection,
            resumeSeconds: resumeSeconds,
            isTVOS: isTVOS
        ) else {
            return nil
        }

        let now = Date()
        if let entry = startupPreheatCache[key], entry.isValid(at: now) {
            return entry.result
        }

        if let task = startupPreheatInFlight[key] {
            return await task.value
        }

        _ = runtimeSeconds
        return nil
    }

    public func startupPreheatResult(
        for selection: PlaybackAssetSelection,
        resumeSeconds: Double,
        runtimeSeconds: Double?,
        isTVOS: Bool
    ) async -> PlaybackStartupPreheater.Result? {
        guard shouldAttemptStartupPreheat(
            selection: selection,
            resumeSeconds: resumeSeconds,
            runtimeSeconds: runtimeSeconds,
            isTVOS: isTVOS
        ) else {
            return nil
        }

        guard let key = startupPreheatKey(
            for: selection,
            resumeSeconds: resumeSeconds,
            isTVOS: isTVOS
        ) else {
            return nil
        }

        let now = Date()
        if let entry = startupPreheatCache[key], entry.isValid(at: now) {
            return entry.result
        }

        if let task = startupPreheatInFlight[key] {
            return await task.value
        }

        _ = runtimeSeconds
        return nil
    }

    public func warmServerBaselineIfNeeded(
        selection: PlaybackAssetSelection,
        isTVOS: Bool
    ) async -> PlaybackServerNetworkBaseline.Result? {
        guard PlaybackServerNetworkBaseline.isEligible(selection: selection) else {
            return nil
        }

        let key = serverBaselineKey(for: selection, isTVOS: isTVOS)
        return await resolveServerBaseline(
            key: key,
            selection: selection,
            isTVOS: isTVOS
        )
    }

    public func serverBaselineResult(
        for selection: PlaybackAssetSelection,
        isTVOS: Bool
    ) async -> PlaybackServerNetworkBaseline.Result? {
        guard PlaybackServerNetworkBaseline.isEligible(selection: selection) else {
            return nil
        }

        let key = serverBaselineKey(for: selection, isTVOS: isTVOS)
        let now = Date()
        if let entry = serverBaselineCache[key], entry.isValid(at: now) {
            return entry.result
        }

        if let task = serverBaselineInFlight[key] {
            return await task.value
        }

        serverBaselineCache[key] = nil
        return nil
    }

    public func cancel(itemID: String) async {
        inFlight[itemID]?.cancel()
        inFlight[itemID] = nil

        for key in startupPreheatInFlight.keys where key.itemID == itemID {
            startupPreheatInFlight[key]?.cancel()
            startupPreheatInFlight[key] = nil
        }
    }

    public func trim(keeping itemIDs: [String]) async {
        let keep = Set(itemIDs)

        for key in inFlight.keys where !keep.contains(key) {
            inFlight[key]?.cancel()
            inFlight[key] = nil
        }

        cache = cache.filter { keep.contains($0.key) }
        startupPreheatCache = startupPreheatCache.filter { keep.contains($0.key.itemID) }

        for key in startupPreheatInFlight.keys where !keep.contains(key.itemID) {
            startupPreheatInFlight[key]?.cancel()
            startupPreheatInFlight[key] = nil
        }
    }

    public func invalidate(itemID: String) async {
        cache[itemID] = nil
        inFlight[itemID]?.cancel()
        inFlight[itemID] = nil

        startupPreheatCache = startupPreheatCache.filter { $0.key.itemID != itemID }
        for key in startupPreheatInFlight.keys where key.itemID == itemID {
            startupPreheatInFlight[key]?.cancel()
            startupPreheatInFlight[key] = nil
        }
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

    private func shouldAttemptStartupPreheat(
        selection: PlaybackAssetSelection,
        resumeSeconds: Double,
        runtimeSeconds: Double?,
        isTVOS: Bool
    ) -> Bool {
        return PlaybackStartupReadinessPolicy.requiresStartupPreheat(
            route: selection.decision.route,
            sourceBitrate: selection.source.bitrate,
            runtimeSeconds: runtimeSeconds,
            resumeSeconds: resumeSeconds,
            isTVOS: isTVOS
        )
    }

    private func resolveStartupPreheat(
        key: StartupPreheatKey,
        selection: PlaybackAssetSelection,
        resumeSeconds: Double,
        runtimeSeconds: Double?,
        isTVOS: Bool
    ) async -> PlaybackStartupPreheater.Result? {
        let now = Date()
        if let entry = startupPreheatCache[key], entry.isValid(at: now) {
            return entry.result
        }

        if let task = startupPreheatInFlight[key] {
            return await task.value
        }

        let sanitizedResume = max(0, resumeSeconds.isFinite ? resumeSeconds : 0)
        let startupPreheater = startupPreheater
        let task = Task<PlaybackStartupPreheater.Result?, Never> {
            await startupPreheater(selection, sanitizedResume, runtimeSeconds, isTVOS)
        }
        startupPreheatInFlight[key] = task

        let result = await task.value
        startupPreheatInFlight[key] = nil
        if let result {
            startupPreheatCache[key] = StartupPreheatEntry(
                result: result,
                expirationDate: Date().addingTimeInterval(ttl)
            )
        }
        return result
    }

    private func resolveServerBaseline(
        key: ServerBaselineKey,
        selection: PlaybackAssetSelection,
        isTVOS: Bool
    ) async -> PlaybackServerNetworkBaseline.Result? {
        let now = Date()
        if let entry = serverBaselineCache[key], entry.isValid(at: now) {
            return entry.result
        }

        if let task = serverBaselineInFlight[key] {
            return await task.value
        }

        let serverBaselineWarmer = serverBaselineWarmer
        let task = Task<PlaybackServerNetworkBaseline.Result?, Never> {
            await serverBaselineWarmer(selection, isTVOS)
        }
        serverBaselineInFlight[key] = task

        let result = await task.value
        serverBaselineInFlight[key] = nil
        if let result {
            serverBaselineCache[key] = ServerBaselineEntry(
                result: result,
                expirationDate: Date().addingTimeInterval(min(ttl, PlaybackServerNetworkBaseline.maximumAge))
            )
        }
        return result
    }

    private func serverBaselineKey(
        for selection: PlaybackAssetSelection,
        isTVOS: Bool
    ) -> ServerBaselineKey {
        ServerBaselineKey(
            serverKey: PlaybackServerNetworkBaseline.serverKey(for: selection.assetURL),
            networkScope: PlaybackServerNetworkBaseline.defaultNetworkScope,
            isTVOS: isTVOS
        )
    }

    private func startupPreheatKey(
        for selection: PlaybackAssetSelection,
        resumeSeconds: Double,
        isTVOS: Bool
    ) -> StartupPreheatKey? {
        guard shouldPreheat(selection: selection, resumeSeconds: resumeSeconds) else {
            return nil
        }

        return StartupPreheatKey(
            itemID: selection.source.itemID,
            sourceID: selection.source.id,
            routeSignature: MediaGatewayCacheKey.routeSignature(
                for: selection.assetURL,
                headers: selection.headers
            ),
            routeKind: routeKind(for: selection.decision.route),
            resumeBucket: MediaGatewayCacheKey.resumeBucket(for: resumeSeconds),
            isTVOS: isTVOS
        )
    }

    private func shouldPreheat(selection: PlaybackAssetSelection, resumeSeconds: Double) -> Bool {
        switch selection.decision.route {
        case .directPlay:
            return true
        case .nativeBridge, .remux, .transcode:
            return resumeSeconds <= 0
        }
    }

    private func routeKind(for route: PlaybackRoute) -> String {
        switch route {
        case .directPlay:
            return "directPlay"
        case .nativeBridge:
            return "nativeBridge"
        case .remux:
            return "remux"
        case .transcode:
            return "transcode"
        }
    }

    private static func makeDefaultStartupPreheater() -> @Sendable (
        PlaybackAssetSelection,
        Double,
        Double?,
        Bool
    ) async -> PlaybackStartupPreheater.Result? {
        { selection, resumeSeconds, runtimeSeconds, isTVOS in
            await PlaybackStartupPreheater.preheat(
                selection: selection,
                resumeSeconds: resumeSeconds,
                runtimeSeconds: runtimeSeconds,
                isTVOS: isTVOS
            )
        }
    }

    private static func makeDefaultServerBaselineWarmer() -> @Sendable (
        PlaybackAssetSelection,
        Bool
    ) async -> PlaybackServerNetworkBaseline.Result? {
        { selection, isTVOS in
            await PlaybackServerNetworkBaseline.warm(
                selection: selection,
                isTVOS: isTVOS
            )
        }
    }
}
