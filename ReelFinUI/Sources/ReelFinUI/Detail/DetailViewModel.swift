import Foundation
import PlaybackEngine
import Shared

@MainActor
final class DetailViewModel: ObservableObject {
    enum LoadPhase: Int {
        case shell
        case hero
        case content
        case playbackWarm
    }

    @Published var detail: MediaDetail
    @Published var loadPhase: LoadPhase = .shell
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var playbackProgress: PlaybackProgress?
    @Published var isInWatchlist = false
    @Published var isWatched = false
    @Published var preferredPlaybackSource: MediaSource?
    @Published var playbackOptimizationStatus: ApplePlaybackOptimizationStatus?
    @Published var isPlaybackWarm = false
    @Published var isWarmingPlayback = false

    @Published var seasons: [MediaItem] = []
    @Published var episodes: [MediaItem] = []
    @Published var selectedSeason: MediaItem?
    @Published var isLoadingEpisodes = false
    @Published var nextUpEpisode: MediaItem?

    private let dependencies: ReelFinDependencies
    private var preferredEpisode: MediaItem?
    private var activeLoadToken = UUID()
    private var playbackWarmupRequestToken = UUID()
    private var playbackWarmupRequestItemID: String?
    private var backgroundTasks: [Task<Void, Never>] = []
    private var loadedItemID: String?

    private static var isTVOSPlatform: Bool {
#if os(tvOS)
        true
#else
        false
#endif
    }

    init(item: MediaItem, preferredEpisode: MediaItem? = nil, dependencies: ReelFinDependencies) {
        self.detail = MediaDetail(item: item)
        self.preferredEpisode = preferredEpisode
        self.dependencies = dependencies
        syncDerivedFlags()
    }

    func setDetailItem(_ item: MediaItem, preferredEpisode: MediaItem? = nil) {
        cancelBackgroundTasks()
        activeLoadToken = UUID()
        playbackWarmupRequestToken = UUID()
        playbackWarmupRequestItemID = nil
        loadedItemID = nil
        detail = MediaDetail(item: item)
        self.preferredEpisode = preferredEpisode
        playbackProgress = nil
        preferredPlaybackSource = nil
        playbackOptimizationStatus = nil
        isPlaybackWarm = false
        isWarmingPlayback = false
        seasons = []
        episodes = []
        selectedSeason = nil
        nextUpEpisode = nil
        errorMessage = nil
        loadPhase = .shell
        syncDerivedFlags()
    }

    func load() async {
        let itemID = detail.item.id
        guard loadedItemID != itemID else { return }

        cancelBackgroundTasks()
        loadedItemID = itemID
        activeLoadToken = UUID()
        let loadToken = activeLoadToken

        errorMessage = nil
        isLoading = false
        loadPhase = .shell

        if let cached = await dependencies.detailRepository.cachedItem(id: itemID) {
            detail.item = mergedItem(current: detail.item, incoming: cached)
        }
        syncDerivedFlags()
        playbackProgress = await resolvedPlaybackProgress(for: detail.item)

        backgroundTasks = buildLoadTasks(itemID: itemID, loadToken: loadToken)
    }

    func select(season: MediaItem) async {
        await loadEpisodes(for: season, loadToken: activeLoadToken)
    }

    func selectSeasonIfNeeded(_ season: MediaItem) async {
        guard selectedSeason?.id != season.id || episodes.isEmpty else { return }
        await loadEpisodes(for: season, loadToken: activeLoadToken)
    }

    func prepareEpisodePlayback(_ episode: MediaItem) {
        preferredEpisode = episode
        nextUpEpisode = episode
        syncDerivedFlags()

        let loadToken = activeLoadToken
        let requestToken = beginPlaybackWarmupRequest(itemID: episode.id)
        startPlaybackWarmup(
            for: episode,
            loadToken: loadToken,
            requestToken: requestToken,
            priority: .userInitiated
        )
    }

    var shouldShowResume: Bool {
        guard let playbackProgress else { return false }
        return playbackProgress.positionTicks > 0 && playbackProgress.progressRatio < 0.97
    }

    var playButtonLabel: String {
        if detail.item.mediaType == .series {
            if let episode = nextUpEpisode,
               let season = episode.parentIndexNumber,
               let index = episode.indexNumber {
                return shouldShowResume ? "Resume S\(season) E\(index)" : "Play S\(season) E\(index)"
            }
            return shouldShowResume ? "Resume" : "Play"
        }

        return shouldShowResume ? "Resume" : "Play"
    }

    var playbackStatusText: String? {
        if shouldShowResume, let displayText = playbackProgressDisplayText ?? itemToPlay.playbackPositionDisplayText {
            return "Stopped at \(displayText)"
        }

        if isPlaybackWarm {
            return "Ready to play"
        }

        if itemToPlay.isPlayed || detail.item.isPlayed || isWatched {
            return "Watched"
        }

        return nil
    }

    var itemToPlay: MediaItem {
        if detail.item.mediaType == .series, let nextUpEpisode {
            return nextUpEpisode
        }
        return detail.item
    }

    var selectedEpisodeID: String? {
        detail.item.mediaType == .series ? nextUpEpisode?.id : detail.item.id
    }

    func nextEpisodes(after episode: MediaItem) -> [MediaItem] {
        guard let currentIndex = episodes.firstIndex(where: { $0.id == episode.id }) else {
            return []
        }

        let nextIndex = episodes.index(after: currentIndex)
        guard nextIndex < episodes.endIndex else {
            return []
        }

        return Array(episodes[nextIndex...])
    }

    func toggleWatchlist() {
        let targetValue = !isInWatchlist
        detail.item.isFavorite = targetValue
        isInWatchlist = targetValue

        Task {
            do {
                try await dependencies.apiClient.setFavorite(itemID: detail.item.id, isFavorite: targetValue)
            } catch {
                await MainActor.run {
                    self.detail.item.isFavorite.toggle()
                    self.isInWatchlist.toggle()
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func toggleWatched() {
        let targetItemID = itemToPlay.id
        let targetValue = !isWatched
        let snapshot = watchedMutationSnapshot(for: targetItemID)

        applyWatchedState(targetValue, to: targetItemID)

        Task {
            do {
                try await dependencies.apiClient.setPlayedState(itemID: targetItemID, isPlayed: targetValue)
            } catch {
                await MainActor.run {
                    self.restoreWatchedSnapshot(snapshot)
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func buildLoadTasks(itemID: String, loadToken: UUID) -> [Task<Void, Never>] {
        var tasks: [Task<Void, Never>] = []

        tasks.append(Task(priority: .userInitiated) { [weak self] in
            await self?.refreshHeroItem(itemID: itemID, loadToken: loadToken)
        })

        tasks.append(Task(priority: .utility) { [weak self] in
            await self?.refreshEditorialContent(itemID: itemID, loadToken: loadToken)
        })

        if detail.item.mediaType == .series {
            tasks.append(Task(priority: .userInitiated) { [weak self] in
                await self?.loadSeriesContext(seriesID: itemID, loadToken: loadToken)
            })
        } else {
            let playbackItem = detail.item
            let playbackRequestToken = beginPlaybackWarmupRequest(itemID: playbackItem.id)
            startPlaybackWarmup(
                for: playbackItem,
                loadToken: loadToken,
                requestToken: playbackRequestToken,
                priority: .utility
            )
        }

        return tasks
    }

    private func refreshHeroItem(itemID: String, loadToken: UUID) async {
        do {
            let refreshedItem = try await dependencies.detailRepository.refreshItem(id: itemID)
            guard isActive(loadToken: loadToken, itemID: itemID) else { return }

            detail.item = mergedItem(current: detail.item, incoming: refreshedItem)
            syncDerivedFlags()
            playbackProgress = await resolvedPlaybackProgress(for: detail.item)
            advancePhase(to: .hero)
        } catch {
            guard isActive(loadToken: loadToken, itemID: itemID) else { return }
            if detail.item.overview == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func refreshEditorialContent(itemID: String, loadToken: UUID) async {
        do {
            let refreshedDetail = try await dependencies.detailRepository.loadDetail(id: itemID)
            guard isActive(loadToken: loadToken, itemID: itemID) else { return }

            detail.item = mergedItem(current: detail.item, incoming: refreshedDetail.item)
            detail.similar = refreshedDetail.similar
            detail.cast = refreshedDetail.cast
            syncDerivedFlags()
            advancePhase(to: .content)
            await DetailPresentationTelemetry.shared.markMetadataReady(for: itemID)

            await dependencies.apiClient.prefetchImages(for: refreshedDetail.similar.prefix(4).map { $0 })
        } catch {
            guard isActive(loadToken: loadToken, itemID: itemID) else { return }
            if detail.cast.isEmpty, detail.similar.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadSeriesContext(seriesID: String, loadToken: UUID) async {
        do {
            let playbackRequestToken = playbackWarmupRequestToken
            async let seasonsRequest = dependencies.detailRepository.loadSeasons(seriesID: seriesID)
            async let nextUpRequest = dependencies.detailRepository.loadNextUpEpisode(seriesID: seriesID)

            let fetchedSeasons = try await seasonsRequest
            guard isActive(loadToken: loadToken, itemID: seriesID) else { return }

            seasons = fetchedSeasons
            advancePhase(to: .content)

            let targetEpisode: MediaItem?
            if let preferredEpisode {
                targetEpisode = preferredEpisode
            } else {
                targetEpisode = try? await nextUpRequest
            }

            let targetSeason = targetEpisode.flatMap {
                seasonMatching(preferredEpisode: $0, seasons: fetchedSeasons)
            } ?? fetchedSeasons.first

            if let targetSeason {
                await loadEpisodes(for: targetSeason, loadToken: loadToken)
                guard isActive(loadToken: loadToken, itemID: seriesID) else { return }
                guard isCurrentPlaybackWarmupGeneration(playbackRequestToken) else { return }

                if let targetEpisode {
                    if let matchingEpisode = episodes.first(where: { $0.id == targetEpisode.id }) {
                        nextUpEpisode = mergedEpisode(matchingEpisode, preferred: targetEpisode)
                    } else {
                        nextUpEpisode = targetEpisode
                    }
                } else {
                    nextUpEpisode = episodes.first(where: { !$0.isPlayed }) ?? episodes.first
                }
            }

            guard isActive(loadToken: loadToken, itemID: seriesID) else { return }
            guard isCurrentPlaybackWarmupGeneration(playbackRequestToken) else { return }

            if let nextUpEpisode {
                playbackProgress = await resolvedPlaybackProgress(for: nextUpEpisode)
                guard isActive(loadToken: loadToken, itemID: seriesID) else { return }
                guard isCurrentPlaybackWarmupGeneration(playbackRequestToken) else { return }

                let requestToken = beginPlaybackWarmupRequest(itemID: nextUpEpisode.id)
                startPlaybackWarmup(
                    for: nextUpEpisode,
                    loadToken: loadToken,
                    requestToken: requestToken,
                    priority: .utility
                )
            }
            syncDerivedFlags()
        } catch {
            guard isActive(loadToken: loadToken, itemID: seriesID) else { return }
            AppLog.ui.error("Series context load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadEpisodes(for season: MediaItem, loadToken: UUID) async {
        let playbackRequestToken = playbackWarmupRequestToken
        selectedSeason = season
        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }

        do {
            let fetchedEpisodes = try await dependencies.detailRepository.loadEpisodes(
                seriesID: detail.item.id,
                seasonID: season.id
            )
            guard isActive(loadToken: loadToken, itemID: detail.item.id) else { return }

            episodes = fetchedEpisodes

            if let preferredEpisode,
               let matchedEpisode = fetchedEpisodes.first(where: { $0.id == preferredEpisode.id }) {
                nextUpEpisode = mergedEpisode(matchedEpisode, preferred: preferredEpisode)
            } else if nextUpEpisode == nil {
                nextUpEpisode = fetchedEpisodes.first
            }

            if let nextUpEpisode {
                guard isCurrentPlaybackWarmupGeneration(playbackRequestToken) else { return }
                let progress = await resolvedPlaybackProgress(for: nextUpEpisode)
                guard isCurrentPlaybackWarmupGeneration(playbackRequestToken) else { return }
                playbackProgress = progress
            }
            syncDerivedFlags()
        } catch {
            guard isActive(loadToken: loadToken, itemID: detail.item.id) else { return }
            AppLog.ui.error("Episodes load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startPlaybackWarmup(
        for item: MediaItem,
        loadToken: UUID,
        requestToken: UUID,
        priority: TaskPriority
    ) {
        Task(priority: priority) { [weak self] in
            guard let self else { return }
            await self.runPlaybackWarmup(for: item, loadToken: loadToken, requestToken: requestToken)
        }
    }

    private func runPlaybackWarmup(
        for item: MediaItem,
        loadToken: UUID,
        requestToken: UUID
    ) async {
        guard isActive(loadToken: loadToken, itemID: detail.item.id) else { return }
        guard isCurrentPlaybackWarmupRequest(requestToken, itemID: item.id) else { return }

        isWarmingPlayback = true
        defer {
            if isCurrentPlaybackWarmupRequest(requestToken, itemID: item.id) {
                isWarmingPlayback = false
            }
        }

        let progress = await resolvedPlaybackProgress(for: item)
        guard isActive(loadToken: loadToken, itemID: detail.item.id) else { return }
        guard isCurrentPlaybackWarmupRequest(requestToken, itemID: item.id) else { return }

        playbackProgress = progress

        await dependencies.playbackWarmupManager.warm(
            itemID: item.id,
            resumeSeconds: Self.resumeSeconds(from: progress, item: item),
            runtimeSeconds: Self.runtimeSeconds(for: item),
            isTVOS: Self.isTVOSPlatform
        )
        let selection = await dependencies.playbackWarmupManager.selection(for: item.id)

        guard isActive(loadToken: loadToken, itemID: detail.item.id) else { return }
        guard isCurrentPlaybackWarmupRequest(requestToken, itemID: item.id) else { return }

        preferredPlaybackSource = selection?.source
        playbackOptimizationStatus = ApplePlaybackOptimizationStatus(selection: selection)
        isPlaybackWarm = selection != nil

        if selection != nil {
            advancePhase(to: .playbackWarm)
            await DetailPresentationTelemetry.shared.markPlayReady(for: item.id)
        }
    }

    private func cancelBackgroundTasks() {
        backgroundTasks.forEach { $0.cancel() }
        backgroundTasks.removeAll()
        playbackWarmupRequestToken = UUID()
        playbackWarmupRequestItemID = nil
    }

    private func isActive(loadToken: UUID, itemID: String) -> Bool {
        activeLoadToken == loadToken && detail.item.id == itemID
    }

    private func beginPlaybackWarmupRequest(itemID: String) -> UUID {
        let requestToken = UUID()
        playbackWarmupRequestToken = requestToken
        playbackWarmupRequestItemID = itemID
        return requestToken
    }

    private func isCurrentPlaybackWarmupGeneration(_ requestToken: UUID) -> Bool {
        playbackWarmupRequestToken == requestToken
    }

    private func isCurrentPlaybackWarmupRequest(_ requestToken: UUID, itemID: String) -> Bool {
        playbackWarmupRequestToken == requestToken && playbackWarmupRequestItemID == itemID
    }

    private func advancePhase(to phase: LoadPhase) {
        guard phase.rawValue > loadPhase.rawValue else { return }
        loadPhase = phase
    }

    private func seasonMatching(preferredEpisode: MediaItem, seasons: [MediaItem]) -> MediaItem? {
        if let seasonNumber = preferredEpisode.parentIndexNumber,
           let exact = seasons.first(where: { $0.indexNumber == seasonNumber }) {
            return exact
        }

        if let parentID = preferredEpisode.parentID,
           let exact = seasons.first(where: { $0.id == parentID }) {
            return exact
        }

        return seasons.first
    }

    private func resolvedPlaybackProgress(for item: MediaItem) async -> PlaybackProgress? {
        let local = try? await dependencies.repository.fetchPlaybackProgress(itemID: item.id)
        return PlaybackProgress.resolvedResumeProgress(
            for: item,
            localProgress: local
        )
    }

    private static func resumeSeconds(from progress: PlaybackProgress?, item: MediaItem) -> Double {
        if let positionTicks = progress?.positionTicks, positionTicks > 0 {
            return Double(positionTicks) / 10_000_000
        }

        if let positionTicks = item.playbackPositionTicks, positionTicks > 0 {
            return Double(positionTicks) / 10_000_000
        }

        return 0
    }

    private static func runtimeSeconds(for item: MediaItem) -> Double? {
        guard let runtimeTicks = item.runtimeTicks, runtimeTicks > 0 else {
            return nil
        }
        return Double(runtimeTicks) / 10_000_000
    }

    private func mergedEpisode(_ item: MediaItem, preferred: MediaItem) -> MediaItem {
        var merged = item
        if merged.isFavorite == false {
            merged.isFavorite = preferred.isFavorite
        }
        if merged.playbackPositionTicks == nil {
            merged.playbackPositionTicks = preferred.playbackPositionTicks
        }
        if merged.runtimeTicks == nil {
            merged.runtimeTicks = preferred.runtimeTicks
        }
        if merged.parentIndexNumber == nil {
            merged.parentIndexNumber = preferred.parentIndexNumber
        }
        if merged.indexNumber == nil {
            merged.indexNumber = preferred.indexNumber
        }
        return merged
    }

    private func mergedItem(current: MediaItem, incoming: MediaItem) -> MediaItem {
        var merged = incoming
        if merged.isFavorite == false {
            merged.isFavorite = current.isFavorite
        }
        if merged.playbackPositionTicks == nil {
            merged.playbackPositionTicks = current.playbackPositionTicks
        }
        if merged.runtimeTicks == nil {
            merged.runtimeTicks = current.runtimeTicks
        }
        if merged.seriesName == nil {
            merged.seriesName = current.seriesName
        }
        if merged.seriesPosterTag == nil {
            merged.seriesPosterTag = current.seriesPosterTag
        }
        if merged.parentID == nil {
            merged.parentID = current.parentID
        }
        return merged
    }

    private var playbackProgressDisplayText: String? {
        guard let playbackProgress, playbackProgress.positionTicks > 0 else { return nil }
        let totalSeconds = Int(playbackProgress.positionTicks / 10_000_000)
        let totalMinutes = max(0, totalSeconds / 60)
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if minutes == 0 {
            return "\(hours)h"
        }
        return String(format: "%dh%02d", hours, minutes)
    }

    private func syncDerivedFlags() {
        isInWatchlist = detail.item.isFavorite
        isWatched = itemToPlay.isPlayed
    }

    private func applyWatchedState(_ isPlayed: Bool, to itemID: String) {
        updateEpisode(itemID: itemID) { item in
            item.isPlayed = isPlayed
            item.playbackPositionTicks = isPlayed ? nil : item.playbackPositionTicks
        }

        if detail.item.id == itemID {
            detail.item.isPlayed = isPlayed
            if isPlayed {
                detail.item.playbackPositionTicks = nil
            }
        }

        if nextUpEpisode?.id == itemID {
            if isPlayed, detail.item.mediaType == .series {
                nextUpEpisode = nextUnplayedEpisode(after: itemID)
                    ?? episodes.first(where: { !$0.isPlayed })
                    ?? episodes.first(where: { $0.id == itemID })
                    ?? nextUpEpisode
            } else {
                nextUpEpisode = episodes.first(where: { $0.id == itemID }) ?? nextUpEpisode
            }
        }

        preferredEpisode = nextUpEpisode
        playbackProgress = nil
        syncDerivedFlags()
    }

    private func updateEpisode(itemID: String, transform: (inout MediaItem) -> Void) {
        guard let index = episodes.firstIndex(where: { $0.id == itemID }) else { return }
        transform(&episodes[index])
    }

    private func nextUnplayedEpisode(after itemID: String) -> MediaItem? {
        guard let currentIndex = episodes.firstIndex(where: { $0.id == itemID }) else {
            return episodes.first(where: { !$0.isPlayed })
        }

        let tail = episodes.suffix(from: episodes.index(after: currentIndex))
        return tail.first(where: { !$0.isPlayed })
    }

    private func watchedMutationSnapshot(for itemID: String) -> (detailItem: MediaItem, episodes: [MediaItem], nextUp: MediaItem?, preferred: MediaItem?, itemID: String) {
        (detail.item, episodes, nextUpEpisode, preferredEpisode, itemID)
    }

    private func restoreWatchedSnapshot(_ snapshot: (detailItem: MediaItem, episodes: [MediaItem], nextUp: MediaItem?, preferred: MediaItem?, itemID: String)) {
        detail.item = snapshot.detailItem
        episodes = snapshot.episodes
        nextUpEpisode = snapshot.nextUp
        preferredEpisode = snapshot.preferred
        if let current = nextUpEpisode ?? (detail.item.id == snapshot.itemID ? detail.item : nil) {
            Task {
                let progress = await resolvedPlaybackProgress(for: current)
                await MainActor.run {
                    self.playbackProgress = progress
                    self.syncDerivedFlags()
                }
            }
        } else {
            syncDerivedFlags()
        }
    }
}
