import PlaybackEngine
import Foundation
import Shared

@MainActor
final class ServerSettingsViewModel: ObservableObject {
    @Published var serverURLText = ""
    @Published var username = ""
    @Published var allowCellularStreaming = true
    @Published var preferredQuality: QualityPreference = .auto
    @Published var playbackStrategy: PlaybackStrategy = .bestQualityFastest
    @Published var infoMessage: String?
    @Published var errorMessage: String?
    @Published var isRunningDiagnostics = false
    @Published var diagnosticsLoopCount = 2
    @Published var diagnosticsSampleSize = 8
    @Published var diagnosticsReport: String?

    private let dependencies: ReelFinDependencies

    init(dependencies: ReelFinDependencies) {
        self.dependencies = dependencies

        if let config = dependencies.settingsStore.serverConfiguration {
            serverURLText = config.serverURL.absoluteString
            allowCellularStreaming = config.allowCellularStreaming
            preferredQuality = config.preferredQuality
            playbackStrategy = config.playbackStrategy
        }

        if let session = dependencies.settingsStore.lastSession {
            username = session.username
        }
    }

    func save() async {
        errorMessage = nil
        infoMessage = nil

        do {
            guard let url = URL(string: serverURLText), url.host != nil else {
                throw AppError.invalidServerURL
            }

            let config = ServerConfiguration(
                serverURL: url,
                allowCellularStreaming: allowCellularStreaming,
                preferredQuality: preferredQuality,
                playbackStrategy: playbackStrategy
            )
            try await dependencies.apiClient.configure(server: config)
            dependencies.settingsStore.serverConfiguration = config
            infoMessage = "Settings saved"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func testConnection() async {
        errorMessage = nil
        infoMessage = nil

        do {
            guard let url = URL(string: serverURLText), url.host != nil else {
                throw AppError.invalidServerURL
            }
            try await dependencies.apiClient.testConnection(serverURL: url)
            infoMessage = "Connection OK"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runPlaybackDiagnostics() async {
        errorMessage = nil
        infoMessage = nil
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
}
