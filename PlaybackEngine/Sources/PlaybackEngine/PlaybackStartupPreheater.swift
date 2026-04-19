import Foundation
import Shared

public enum PlaybackStartupPreheater {
    public struct Result: Sendable, Equatable {
        public let byteCount: Int
        public let elapsedSeconds: Double
        public let observedBitrate: Double
        public let rangeStart: Int64?
        public let reason: String

        public init(
            byteCount: Int,
            elapsedSeconds: Double,
            observedBitrate: Double,
            rangeStart: Int64?,
            reason: String
        ) {
            self.byteCount = byteCount
            self.elapsedSeconds = elapsedSeconds
            self.observedBitrate = observedBitrate
            self.rangeStart = rangeStart
            self.reason = reason
        }
    }

    static func preheat(
        selection: PlaybackAssetSelection,
        resumeSeconds: Double,
        runtimeSeconds: Double?,
        isTVOS: Bool,
        urlProtocolClasses: [AnyClass]? = nil
    ) async -> Result? {
        guard !isLocalURL(selection.assetURL) else { return nil }
        guard PlaybackStartupReadinessPolicy.requirement(
            route: selection.decision.route,
            sourceBitrate: selection.source.bitrate,
            runtimeSeconds: runtimeSeconds,
            resumeSeconds: resumeSeconds,
            isTVOS: isTVOS
        ) != nil else {
            return nil
        }

        let requestPlan = makeRequestPlan(
            selection: selection,
            resumeSeconds: resumeSeconds,
            runtimeSeconds: runtimeSeconds,
            isTVOS: isTVOS
        )
        let startedAt = Date()

        do {
            let data = try await fetch(
                requestPlan: requestPlan,
                headers: selection.headers,
                urlProtocolClasses: urlProtocolClasses
            )
            let elapsed = max(0.001, Date().timeIntervalSince(startedAt))
            let result = Result(
                byteCount: data.count,
                elapsedSeconds: elapsed,
                observedBitrate: Double(data.count * 8) / elapsed,
                rangeStart: requestPlan.rangeStart,
                reason: requestPlan.reason
            )
            let rangeStart = result.rangeStart.map(String.init) ?? "none"
            AppLog.playback.info(
                "playback.startup.preheat.done — item=\(selection.source.itemID.prefix(8), privacy: .public) bytes=\(result.byteCount, privacy: .public) elapsed=\(result.elapsedSeconds, format: .fixed(precision: 3)) bitrate=\(Int(result.observedBitrate), privacy: .public) rangeStart=\(rangeStart, privacy: .public) reason=\(result.reason, privacy: .public)"
            )
            return result
        } catch {
            AppLog.playback.debug(
                "playback.startup.preheat.skipped — item=\(selection.source.itemID.prefix(8), privacy: .public) reason=\(requestPlan.reason, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private struct RequestPlan: Sendable {
        let url: URL
        let rangeStart: Int64?
        let rangeLength: Int
        let timeout: TimeInterval
        let reason: String
    }

    private static func makeRequestPlan(
        selection: PlaybackAssetSelection,
        resumeSeconds: Double,
        runtimeSeconds: Double?,
        isTVOS: Bool
    ) -> RequestPlan {
        switch selection.decision.route {
        case .directPlay:
            guard !isPlaylistURL(selection.assetURL) else {
                return playlistProbePlan(url: selection.assetURL, isTVOS: isTVOS)
            }

            let length = isTVOS ? 4 * 1_024 * 1_024 : 2 * 1_024 * 1_024
            let offset = estimatedByteOffset(
                fileSize: selection.source.fileSize,
                runtimeSeconds: runtimeSeconds,
                resumeSeconds: resumeSeconds,
                alignment: Int64(length)
            )
            return RequestPlan(
                url: selection.assetURL,
                rangeStart: offset,
                rangeLength: length,
                timeout: isTVOS ? 2.5 : 1.25,
                reason: "directplay_range"
            )

        case .nativeBridge, .remux, .transcode:
            return playlistProbePlan(url: selection.assetURL, isTVOS: isTVOS)
        }
    }

    private static func playlistProbePlan(url: URL, isTVOS: Bool) -> RequestPlan {
        RequestPlan(
            url: url,
            rangeStart: nil,
            rangeLength: isTVOS ? 512 * 1_024 : 256 * 1_024,
            timeout: isTVOS ? 2 : 1,
            reason: "playlist_probe"
        )
    }

    private static func estimatedByteOffset(
        fileSize: Int64?,
        runtimeSeconds: Double?,
        resumeSeconds: Double,
        alignment: Int64
    ) -> Int64 {
        guard
            let fileSize,
            fileSize > 0,
            let runtimeSeconds,
            runtimeSeconds.isFinite,
            runtimeSeconds > 0,
            resumeSeconds > 0
        else {
            return 0
        }

        let ratio = min(max(resumeSeconds / runtimeSeconds, 0), 0.98)
        let rawOffset = Int64(Double(fileSize) * ratio)
        return max(0, (rawOffset / alignment) * alignment)
    }

    private static func fetch(
        requestPlan: RequestPlan,
        headers: [String: String],
        urlProtocolClasses: [AnyClass]?
    ) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestPlan.timeout
        configuration.timeoutIntervalForResource = requestPlan.timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 2
        if let urlProtocolClasses {
            configuration.protocolClasses = urlProtocolClasses + (configuration.protocolClasses ?? [])
        }
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: requestPlan.url)
        request.timeoutInterval = requestPlan.timeout
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let rangeStart = requestPlan.rangeStart {
            let end = rangeStart + Int64(requestPlan.rangeLength) - 1
            request.setValue("bytes=\(rangeStart)-\(end)", forHTTPHeaderField: "Range")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.network("Startup preheat returned a non-HTTP response.")
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw AppError.network("Startup preheat failed (\(httpResponse.statusCode)).")
        }

        if requestPlan.rangeStart == nil, data.count > requestPlan.rangeLength {
            return Data(data.prefix(requestPlan.rangeLength))
        }

        return data
    }

    private static func isLocalURL(_ url: URL) -> Bool {
        url.host == "127.0.0.1" || url.host == "localhost"
    }

    private static func isPlaylistURL(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        return pathExtension == "m3u8" || pathExtension == "m3u"
    }
}
