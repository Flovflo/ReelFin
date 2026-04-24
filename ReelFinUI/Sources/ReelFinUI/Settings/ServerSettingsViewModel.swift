import PlaybackEngine
import Foundation
import Shared

enum ServerSettingsSaveResult {
    case saved
    case requiresReauthentication
    case failed
}

enum HomeSectionMoveDirection {
    case up
    case down
}

@MainActor
final class ServerSettingsViewModel: ObservableObject {
    @Published var serverURLText = ""
    @Published var username = ""
    @Published var preferredQuality: QualityPreference = .auto
    @Published var playbackStrategy: PlaybackStrategy = .bestQualityFastest
    @Published var playbackPolicy: PlaybackPolicy = .auto
    @Published var allowSDRFallback = true
    @Published var preferAudioTranscodeOnly = true
    @Published var customBitrateMbpsText = ""
    @Published var preferredAudioLanguage = ""
    @Published var preferredSubtitleLanguage = ""
    @Published var forceH264FallbackWhenNotDirectPlay = true
    @Published var nativeVLCClassPlayerEnabled = false
    @Published var episodeReleaseNotificationsEnabled = false
    @Published var homeOrderedSectionKinds: [HomeSectionKind] = HomeViewModel.defaultSectionOrder
    @Published var homeHiddenSectionKinds: Set<HomeSectionKind> = []
    @Published var localPlaybackBridgeEnabled = true
    @Published var fasterVideoOnlyStartupEnabled = false
    @Published var dolbyVisionPackagingMode: DolbyVisionPackagingMode = .dvProfile81Compatible
    @Published var infoMessage: String?
    @Published var errorMessage: String?
    @Published var isRunningDiagnostics = false
    @Published var diagnosticsLoopCount = 2
    @Published var diagnosticsSampleSize = 8
    @Published var diagnosticsReport: String?

    private let dependencies: ReelFinDependencies
    private let defaults: UserDefaults

    private enum Keys {
        static let localPlaybackBridgeEnabled = "reelfin.playback.localhls.enabled"
        static let fasterVideoOnlyStartupEnabled = "reelfin.playback.localhls.videoOnlyStartup"
        static let dolbyVisionPackagingMode = "reelfin.playback.dv.packagingMode"
    }

    init(
        dependencies: ReelFinDependencies,
        defaults: UserDefaults = .standard
    ) {
        self.dependencies = dependencies
        self.defaults = defaults

        if let config = dependencies.settingsStore.serverConfiguration {
            serverURLText = config.serverURL.absoluteString
            preferredQuality = config.preferredQuality
            playbackStrategy = config.playbackStrategy
            playbackPolicy = config.playbackPolicy
            allowSDRFallback = config.allowSDRFallback
            preferAudioTranscodeOnly = config.preferAudioTranscodeOnly
            forceH264FallbackWhenNotDirectPlay = config.forceH264FallbackWhenNotDirectPlay
            nativeVLCClassPlayerEnabled = config.nativeVLCClassPlayerConfig
                .applyingRuntimeOverride(userDefaults: defaults)
                .enabled
            preferredAudioLanguage = config.preferredAudioLanguage ?? ""
            preferredSubtitleLanguage = config.preferredSubtitleLanguage ?? ""
            customBitrateMbpsText = Self.formatBitrateInput(from: config.maxStreamingBitrateOverride)
        } else {
            nativeVLCClassPlayerEnabled = NativeVLCClassPlayerConfig()
                .applyingRuntimeOverride(userDefaults: defaults)
                .enabled
        }

        let storedHomePreferences = HomeSectionPreferencesStore.load(defaults: defaults)
        homeOrderedSectionKinds = HomeViewModel.sanitizedSectionOrder(from: storedHomePreferences.orderedKinds)
        homeHiddenSectionKinds = Set(
            storedHomePreferences.hiddenKinds.filter { HomeViewModel.supportedSectionKinds.contains($0) }
        )

        localPlaybackBridgeEnabled = defaults.object(forKey: Keys.localPlaybackBridgeEnabled) as? Bool ?? true
        fasterVideoOnlyStartupEnabled = defaults.object(forKey: Keys.fasterVideoOnlyStartupEnabled) as? Bool ?? false
        dolbyVisionPackagingMode = Self.readDolbyVisionPackagingMode(from: defaults)
        episodeReleaseNotificationsEnabled = dependencies.settingsStore.episodeReleaseNotificationsEnabled

        if let session = dependencies.settingsStore.lastSession {
            username = session.username
        }
    }

    var isSignedIn: Bool {
        dependencies.settingsStore.lastSession != nil
    }

    var displayUsername: String {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return isSignedIn ? "Signed In" : "Not Signed In"
    }

    var connectionStatusLabel: String {
        isSignedIn ? "Connected" : "Signed out"
    }

    var displayServerHost: String {
        if let url = try? normalizedServerURL(from: serverURLText) {
            return url.host ?? url.absoluteString
        }

        if let saved = dependencies.settingsStore.serverConfiguration?.serverURL {
            return saved.host ?? saved.absoluteString
        }

        return "No server configured"
    }

    var availableHomeSections: [HomeSectionKind] {
        HomeViewModel.supportedSectionKinds
    }

    var visibleHomeSectionCount: Int {
        availableHomeSections.filter { !homeHiddenSectionKinds.contains($0) }.count
    }

    var homeCustomizationSummary: String {
        let visibleCount = visibleHomeSectionCount
        let orderedVisibleTitles = homeOrderedSectionKinds
            .filter { !homeHiddenSectionKinds.contains($0) }
            .prefix(2)
            .map(Self.homeSectionTitle(for:))
        let lead = orderedVisibleTitles.isEmpty ? "Default order" : orderedVisibleTitles.joined(separator: " / ")
        let pluralizedSection = visibleCount == 1 ? "section" : "sections"
        return "\(visibleCount) \(pluralizedSection) visible | \(lead)"
    }

    var advancedPlaybackSummary: String {
        let bridge = localPlaybackBridgeEnabled ? "Local bridge on" : "Server-only playback"
        let startup = fasterVideoOnlyStartupEnabled ? "fast startup" : "full startup"
        let native = nativeVLCClassPlayerEnabled ? "Native VLC on" : "Native VLC off"
        return "\(native) | \(bridge) | \(startup) | \(Self.dolbyVisionLabel(for: dolbyVisionPackagingMode))"
    }

    var canSave: Bool {
        guard (try? normalizedServerURL(from: serverURLText)) != nil else {
            return false
        }
        return isCustomBitrateInputValid
    }

    var hasPendingServerChange: Bool {
        let trimmed = serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedURL = dependencies.settingsStore.serverConfiguration?.serverURL.absoluteString ?? ""

        guard !trimmed.isEmpty else {
            return !savedURL.isEmpty
        }

        if let normalized = try? normalizedServerURL(from: serverURLText) {
            return normalized.absoluteString != savedURL
        }

        return trimmed != savedURL
    }

    var hasPendingChanges: Bool {
        let saved = dependencies.settingsStore.serverConfiguration

        return hasPendingServerChange
            || preferredQuality != (saved?.preferredQuality ?? .auto)
            || playbackStrategy != (saved?.playbackStrategy ?? .bestQualityFastest)
            || playbackPolicy != (saved?.playbackPolicy ?? .auto)
            || effectiveAllowSDRFallback != (saved?.allowSDRFallback ?? true)
            || preferAudioTranscodeOnly != (saved?.preferAudioTranscodeOnly ?? true)
            || forceH264FallbackWhenNotDirectPlay != (saved?.forceH264FallbackWhenNotDirectPlay ?? false)
            || nativeVLCClassPlayerEnabled != (saved?.nativeVLCClassPlayerConfig.enabled ?? false)
            || normalizedLanguageCode(from: preferredAudioLanguage) != saved?.preferredAudioLanguage
            || normalizedLanguageCode(from: preferredSubtitleLanguage) != saved?.preferredSubtitleLanguage
            || parsedCustomBitrateOverride() != saved?.maxStreamingBitrateOverride
    }

    var saveButtonTitle: String {
        if hasPendingServerChange {
            return "Save & Reconnect"
        }
        return hasPendingChanges ? "Save Changes" : "Saved"
    }

    var bandwidthCapSummary: String {
        if let bitrate = parsedCustomBitrateOverride() {
            return Self.bitrateLabel(for: bitrate)
        }
        return "Use quality preset"
    }

    var effectivePreferredAudioLanguage: String? {
        normalizedLanguageCode(from: preferredAudioLanguage)
    }

    var effectivePreferredSubtitleLanguage: String? {
        normalizedLanguageCode(from: preferredSubtitleLanguage)
    }

    var customBitrateFieldHint: String {
        isCustomBitrateInputValid ? "Leave blank to follow the selected quality preset." : "Enter a positive Mbps value."
    }

    var hasInvalidCustomBitrateInput: Bool {
        let trimmed = customBitrateMbpsText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !isCustomBitrateInputValid
    }

    func serverURLDidChange() {
        clearMessages()
    }

    func save() async -> ServerSettingsSaveResult {
        clearMessages()

        guard isCustomBitrateInputValid else {
            errorMessage = "Enter a valid custom bitrate cap in Mbps or leave it blank."
            return .failed
        }

        do {
            let url = try normalizedServerURL(from: serverURLText)
            let saved = dependencies.settingsStore.serverConfiguration
            let previousURL = saved?.serverURL
            let savedAllowCellularStreaming = saved?.allowCellularStreaming ?? true
            var nativeConfig = saved?.nativeVLCClassPlayerConfig ?? NativeVLCClassPlayerConfig()
            nativeConfig.enabled = nativeVLCClassPlayerEnabled
            nativeConfig.alwaysRequestOriginalFile = true
            nativeConfig.allowServerTranscodeFallback = false
            defaults.set(nativeVLCClassPlayerEnabled, forKey: NativeVLCClassPlayerRuntimeDefaults.enabledKey)
            defaults.set(true, forKey: NativeVLCClassPlayerRuntimeDefaults.experimentalBranchDefaultAppliedKey)

            let configuration = ServerConfiguration(
                serverURL: url,
                allowCellularStreaming: savedAllowCellularStreaming,
                preferredQuality: preferredQuality,
                playbackStrategy: playbackStrategy,
                playbackPolicy: playbackPolicy,
                allowSDRFallback: effectiveAllowSDRFallback,
                preferAudioTranscodeOnly: preferAudioTranscodeOnly,
                maxStreamingBitrateOverride: parsedCustomBitrateOverride(),
                forceH264FallbackWhenNotDirectPlay: forceH264FallbackWhenNotDirectPlay,
                nativeVLCClassPlayerConfig: nativeConfig,
                preferredAudioLanguage: effectivePreferredAudioLanguage,
                preferredSubtitleLanguage: effectivePreferredSubtitleLanguage
            )

            try await dependencies.apiClient.configure(server: configuration)
            dependencies.settingsStore.serverConfiguration = configuration

            if previousURL?.absoluteString != configuration.serverURL.absoluteString {
                return .requiresReauthentication
            }

            infoMessage = "Playback and server settings saved."
            return .saved
        } catch {
            errorMessage = error.localizedDescription
            return .failed
        }
    }

    func testConnection() async {
        clearMessages()

        do {
            let url = try normalizedServerURL(from: serverURLText)
            try await dependencies.apiClient.testConnection(serverURL: url)
            infoMessage = "Connection OK"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshEpisodeReleaseNotificationsState() async {
        let enabled = await dependencies.episodeReleaseNotificationManager.notificationsEnabled()
        episodeReleaseNotificationsEnabled = enabled
    }

    func setEpisodeReleaseNotificationsEnabled(_ enabled: Bool) async {
        clearMessages()

        await dependencies.episodeReleaseNotificationManager.setNotificationsEnabled(enabled)
        let resolvedEnabled = await dependencies.episodeReleaseNotificationManager.notificationsEnabled()
        let authorization = await dependencies.episodeReleaseNotificationManager.authorizationStatus()

        episodeReleaseNotificationsEnabled = resolvedEnabled

        if resolvedEnabled {
            infoMessage = "Episode alerts enabled"
            return
        }

        guard enabled else {
            infoMessage = "Episode alerts disabled"
            return
        }

        switch authorization {
        case .denied:
            errorMessage = "Notifications are disabled for ReelFin in iOS Settings."
        case .notDetermined:
            errorMessage = "Notification permission is still pending."
        case .authorized:
            errorMessage = "Episode alerts could not be enabled."
        case .unsupported:
            errorMessage = "Episode alerts are not available on this device."
        }
    }

    func setNativeVLCClassPlayerEnabled(_ enabled: Bool) {
        nativeVLCClassPlayerEnabled = enabled
        defaults.set(enabled, forKey: NativeVLCClassPlayerRuntimeDefaults.enabledKey)
        defaults.set(true, forKey: NativeVLCClassPlayerRuntimeDefaults.experimentalBranchDefaultAppliedKey)
        if enabled {
            forceH264FallbackWhenNotDirectPlay = false
        }
    }

    func setHomeSectionVisibility(_ kind: HomeSectionKind, isVisible: Bool) {
        if isVisible {
            homeHiddenSectionKinds.remove(kind)
        } else {
            homeHiddenSectionKinds.insert(kind)
        }
        persistHomeSectionPreferences()
    }

    func isHomeSectionVisible(_ kind: HomeSectionKind) -> Bool {
        !homeHiddenSectionKinds.contains(kind)
    }

    func canMoveHomeSection(_ kind: HomeSectionKind, direction: HomeSectionMoveDirection) -> Bool {
        guard let index = homeOrderedSectionKinds.firstIndex(of: kind) else {
            return false
        }

        switch direction {
        case .up:
            return index > 0
        case .down:
            return index < homeOrderedSectionKinds.index(before: homeOrderedSectionKinds.endIndex)
        }
    }

    func moveHomeSection(_ kind: HomeSectionKind, direction: HomeSectionMoveDirection) {
        guard let currentIndex = homeOrderedSectionKinds.firstIndex(of: kind) else {
            return
        }

        let destinationIndex: Int
        switch direction {
        case .up:
            guard currentIndex > 0 else { return }
            destinationIndex = currentIndex - 1
        case .down:
            guard currentIndex < homeOrderedSectionKinds.index(before: homeOrderedSectionKinds.endIndex) else { return }
            destinationIndex = currentIndex + 1
        }

        homeOrderedSectionKinds.swapAt(currentIndex, destinationIndex)
        persistHomeSectionPreferences()
    }

    func resetHomeSectionCustomization() {
        homeOrderedSectionKinds = HomeViewModel.defaultSectionOrder
        homeHiddenSectionKinds = []
        persistHomeSectionPreferences()
    }

    func setLocalPlaybackBridgeEnabled(_ enabled: Bool) {
        localPlaybackBridgeEnabled = enabled
        defaults.set(enabled, forKey: Keys.localPlaybackBridgeEnabled)
    }

    func setFasterVideoOnlyStartupEnabled(_ enabled: Bool) {
        fasterVideoOnlyStartupEnabled = enabled
        defaults.set(enabled, forKey: Keys.fasterVideoOnlyStartupEnabled)
    }

    func setDolbyVisionPackagingMode(_ mode: DolbyVisionPackagingMode) {
        dolbyVisionPackagingMode = mode
        defaults.set(mode.rawValue, forKey: Keys.dolbyVisionPackagingMode)
    }

    func resetAdvancedPlaybackDefaults() {
        setLocalPlaybackBridgeEnabled(true)
        setFasterVideoOnlyStartupEnabled(false)
        setDolbyVisionPackagingMode(.dvProfile81Compatible)
        infoMessage = "Advanced playback settings reset."
    }

    func runPlaybackDiagnostics() async {
        clearMessages()
        diagnosticsReport = nil
        isRunningDiagnostics = true
        defer { isRunningDiagnostics = false }

        let loopCount = max(1, min(10, diagnosticsLoopCount))
        let sampleSize = max(1, min(30, diagnosticsSampleSize))
        let coordinator = PlaybackCoordinator(
            apiClient: dependencies.apiClient,
            decisionEngine: PlaybackDecisionEngine()
        )

        var totalChecks = 0
        var totalPassed = 0
        var reportLines: [String] = []
        reportLines.append("Playback diagnostics started")
        reportLines.append("Loops: \(loopCount), sample size per loop: \(sampleSize)")

        do {
            for loopIndex in 1 ... loopCount {
                let feed = try await dependencies.apiClient.fetchHomeFeed(since: nil)
                let candidates = collectCandidates(from: feed, maxItems: sampleSize)
                reportLines.append("Loop \(loopIndex): \(candidates.count) items")

                for item in candidates {
                    totalChecks += 1
                    let line = await validateItem(
                        item: item,
                        coordinator: coordinator
                    )
                    if line.contains("PASS") {
                        totalPassed += 1
                    }
                    reportLines.append(line)
                }
            }

            let totalFailed = totalChecks - totalPassed
            reportLines.append("Summary: \(totalPassed)/\(totalChecks) passed, \(totalFailed) failed")

            diagnosticsReport = reportLines.joined(separator: "\n")
            if totalFailed == 0 {
                infoMessage = "Diagnostics complete: all playback probes passed."
            } else {
                errorMessage = "Diagnostics complete: \(totalFailed) playback probe(s) failed."
            }
        } catch {
            diagnosticsReport = reportLines.joined(separator: "\n")
            errorMessage = "Diagnostics failed: \(error.localizedDescription)"
        }
    }

    private var effectiveAllowSDRFallback: Bool {
        playbackPolicy == .originalLockHDRDV ? false : allowSDRFallback
    }

    private var isCustomBitrateInputValid: Bool {
        let trimmed = customBitrateMbpsText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || parsedCustomBitrateOverride() != nil
    }

    private func parsedCustomBitrateOverride() -> Int? {
        let trimmed = customBitrateMbpsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else {
            return nil
        }

        return Int((value * 1_000_000).rounded())
    }

    private func persistHomeSectionPreferences() {
        let preferences = HomeSectionPreferences(
            orderedKinds: HomeViewModel.sanitizedSectionOrder(from: homeOrderedSectionKinds),
            hiddenKinds: Array(homeHiddenSectionKinds)
        )
        HomeSectionPreferencesStore.save(preferences, defaults: defaults)
    }

    private func clearMessages() {
        errorMessage = nil
        infoMessage = nil
    }

    private func normalizedServerURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppError.invalidServerURL
        }

        let prefixed = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: prefixed), url.host != nil else {
            throw AppError.invalidServerURL
        }

        return url
    }

    private func normalizedLanguageCode(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private func collectCandidates(from feed: HomeFeed, maxItems: Int) -> [MediaItem] {
        var ordered: [MediaItem] = []
        var seen = Set<String>()

        for item in feed.featured {
            if seen.insert(item.id).inserted {
                ordered.append(item)
            }
            if ordered.count >= maxItems { return ordered }
        }

        for row in feed.rows {
            for item in row.items where seen.insert(item.id).inserted {
                ordered.append(item)
                if ordered.count >= maxItems {
                    return ordered
                }
            }
        }

        return ordered
    }

    private func validateItem(
        item: MediaItem,
        coordinator: PlaybackCoordinator
    ) async -> String {
        do {
            let selection = try await coordinator.resolvePlayback(
                itemID: item.id,
                mode: .balanced,
                allowTranscodingFallbackInPerformance: true
            )

            let reachable = await probeSelection(selection)
            if reachable {
                return "PASS | \(item.name) | \(selection.debugInfo.playMethod)"
            }
        } catch {
            return "FAIL | \(item.name) | \(error.localizedDescription)"
        }

        return "FAIL | \(item.name) | no reachable playback URL"
    }

    private func probeSelection(_ selection: PlaybackAssetSelection) async -> Bool {
        var request = URLRequest(url: selection.assetURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/vnd.apple.mpegurl,application/x-mpegURL,*/*", forHTTPHeaderField: "Accept")
        for (key, value) in selection.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                return false
            }

            guard case .transcode = selection.decision.route else {
                return true
            }

            guard
                let manifest = String(data: data, encoding: .utf8),
                manifest.contains("#EXTM3U"),
                let line = manifest
                    .split(whereSeparator: \.isNewline)
                    .map(String.init)
                    .first(where: { !$0.isEmpty && !$0.hasPrefix("#") })
            else {
                return true
            }

            guard let firstURL = resolveSegmentURL(manifestLine: line, masterURL: selection.assetURL) else {
                return true
            }

            let probeURL: URL
            if firstURL.pathExtension.lowercased() == "m3u8" {
                var childRequest = URLRequest(url: firstURL)
                childRequest.httpMethod = "GET"
                childRequest.timeoutInterval = 12
                childRequest.setValue("application/vnd.apple.mpegurl,application/x-mpegURL,*/*", forHTTPHeaderField: "Accept")
                for (key, value) in selection.headers {
                    childRequest.setValue(value, forHTTPHeaderField: key)
                }

                let (childData, childResponse) = try await URLSession.shared.data(for: childRequest)
                guard let childHTTP = childResponse as? HTTPURLResponse, (200 ..< 300).contains(childHTTP.statusCode) else {
                    return false
                }

                guard
                    let childManifest = String(data: childData, encoding: .utf8),
                    childManifest.contains("#EXTM3U"),
                    let childLine = childManifest
                        .split(whereSeparator: \.isNewline)
                        .map(String.init)
                        .first(where: { !$0.isEmpty && !$0.hasPrefix("#") }),
                    let childURL = resolveSegmentURL(manifestLine: childLine, masterURL: firstURL)
                else {
                    return false
                }

                probeURL = childURL
            } else {
                probeURL = firstURL
            }

            var segmentRequest = URLRequest(url: probeURL)
            segmentRequest.httpMethod = "GET"
            segmentRequest.timeoutInterval = 12
            segmentRequest.setValue("bytes=0-2047", forHTTPHeaderField: "Range")
            for (key, value) in selection.headers {
                segmentRequest.setValue(value, forHTTPHeaderField: key)
            }

            let (_, segmentResponse) = try await URLSession.shared.data(for: segmentRequest)
            guard let segmentHTTP = segmentResponse as? HTTPURLResponse else {
                return false
            }
            return (200 ..< 300).contains(segmentHTTP.statusCode) || segmentHTTP.statusCode == 206
        } catch {
            return false
        }
    }

    private func resolveSegmentURL(manifestLine: String, masterURL: URL) -> URL? {
        if let absolute = URL(string: manifestLine), absolute.scheme != nil {
            return absolute
        }

        guard let resolved = URL(string: manifestLine, relativeTo: masterURL)?.absoluteURL else {
            return nil
        }

        guard
            let masterComponents = URLComponents(url: masterURL, resolvingAgainstBaseURL: false),
            let apiKey = masterComponents.queryItems?.first(where: { $0.name.caseInsensitiveCompare("api_key") == .orderedSame })?.value
        else {
            return resolved
        }

        guard var segmentComponents = URLComponents(url: resolved, resolvingAgainstBaseURL: false) else {
            return resolved
        }

        var queryItems = segmentComponents.queryItems ?? []
        if !queryItems.contains(where: { $0.name.caseInsensitiveCompare("api_key") == .orderedSame }) {
            queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
            segmentComponents.queryItems = queryItems
        }

        return segmentComponents.url ?? resolved
    }

    private static func readDolbyVisionPackagingMode(from defaults: UserDefaults) -> DolbyVisionPackagingMode {
        guard let rawValue = defaults.string(forKey: Keys.dolbyVisionPackagingMode) else {
            return .dvProfile81Compatible
        }
        return DolbyVisionPackagingMode(rawValue: rawValue) ?? .dvProfile81Compatible
    }

    private static func formatBitrateInput(from bitrate: Int?) -> String {
        guard let bitrate else { return "" }
        let mbps = Double(bitrate) / 1_000_000
        if mbps.rounded(.towardZero) == mbps {
            return String(Int(mbps))
        }
        return String(format: "%.1f", mbps)
    }

    private static func bitrateLabel(for bitrate: Int) -> String {
        let mbps = Double(bitrate) / 1_000_000
        if mbps >= 10, mbps.rounded(.towardZero) == mbps {
            return "\(Int(mbps)) Mbps"
        }
        return String(format: "%.1f Mbps", mbps)
    }

    private static func homeSectionTitle(for kind: HomeSectionKind) -> String {
        switch kind {
        case .continueWatching:
            return "Continue Watching"
        case .recentlyReleasedMovies:
            return "Recently Released Movies"
        case .recentlyReleasedSeries:
            return "Recently Released TV Shows"
        case .nextUp:
            return "Next Up"
        case .recentlyAddedMovies:
            return "Recently Added Movies"
        case .recentlyAddedSeries:
            return "Recently Added TV"
        case .popular:
            return "Popular"
        case .trending:
            return "Trending"
        case .movies:
            return "Movies"
        case .shows:
            return "Shows"
        case .latest:
            return "Latest"
        }
    }

    private static func dolbyVisionLabel(for mode: DolbyVisionPackagingMode) -> String {
        switch mode {
        case .dvProfile81Compatible:
            return "Compatible"
        case .hdr10OnlyFallback:
            return "HDR10 Fallback"
        case .primaryDolbyVisionExperimental:
            return "Experimental DV-First"
        }
    }
}
