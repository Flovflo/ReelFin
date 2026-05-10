import Foundation
import Shared

public enum PlaybackStartupPreheater {
    private static let mebibyte = 1_024 * 1_024
    private static let highBitrateDirectPlayThreshold = 18_000_000

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
        guard PlaybackStartupReadinessPolicy.requiresStartupPreheat(
            route: selection.decision.route,
            sourceBitrate: selection.source.bitrate,
            runtimeSeconds: runtimeSeconds,
            resumeSeconds: resumeSeconds,
            isTVOS: isTVOS
        ) else {
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
        } catch where isCancellation(error) {
            return nil
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

            let plannedLength = directPlayRangeLength(
                sourceBitrate: selection.source.bitrate,
                isTVOS: isTVOS
            )
            let offset = estimatedByteOffset(
                fileSize: selection.source.fileSize,
                runtimeSeconds: runtimeSeconds,
                resumeSeconds: resumeSeconds,
                alignment: Int64(plannedLength),
                prefersNonZeroHealthProbe: prefersNonZeroDirectPlayHealthProbe(
                    fileSize: selection.source.fileSize,
                    sourceBitrate: selection.source.bitrate,
                    rangeLength: plannedLength,
                    isTVOS: isTVOS
                )
            )
            let length = cappedRangeLength(
                plannedLength,
                fileSize: selection.source.fileSize,
                offset: offset
            )
            return RequestPlan(
                url: selection.assetURL,
                rangeStart: offset,
                rangeLength: length,
                timeout: directPlayRangeTimeout(rangeLength: plannedLength, isTVOS: isTVOS),
                reason: directPlayRangeReason(rangeLength: plannedLength, isTVOS: isTVOS)
            )

        case .nativeBridge, .remux, .transcode:
            return playlistProbePlan(url: selection.assetURL, isTVOS: isTVOS)
        }
    }

    private static func directPlayRangeLength(
        sourceBitrate: Int?,
        isTVOS: Bool
    ) -> Int {
        let baseLength = isTVOS ? 4 * mebibyte : 2 * mebibyte
        guard
            !isTVOS,
            let sourceBitrate,
            sourceBitrate >= highBitrateDirectPlayThreshold
        else {
            return baseLength
        }

        let targetSeconds = 4.5
        let targetBytes = Double(sourceBitrate) / 8 * targetSeconds
        let roundedBytes = Int(ceil(targetBytes / Double(mebibyte))) * mebibyte
        return min(max(roundedBytes, 8 * mebibyte), 12 * mebibyte)
    }

    private static func cappedRangeLength(
        _ rangeLength: Int,
        fileSize: Int64?,
        offset: Int64
    ) -> Int {
        guard let fileSize, fileSize > offset else {
            return rangeLength
        }

        let remainingBytes = fileSize - offset
        return max(1, Int(min(Int64(rangeLength), remainingBytes)))
    }

    private static func directPlayRangeTimeout(rangeLength: Int, isTVOS: Bool) -> TimeInterval {
        guard !isTVOS else { return 2.5 }
        return rangeLength > 2 * mebibyte ? 4 : 1.25
    }

    private static func directPlayRangeReason(rangeLength: Int, isTVOS: Bool) -> String {
        let baseLength = isTVOS ? 4 * mebibyte : 2 * mebibyte
        return rangeLength > baseLength ? "directplay_range_deep" : "directplay_range"
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
        alignment: Int64,
        prefersNonZeroHealthProbe: Bool = false
    ) -> Int64 {
        let startupProbeOffset = nonZeroStartupProbeOffset(
            fileSize: fileSize,
            alignment: alignment,
            prefersNonZeroHealthProbe: prefersNonZeroHealthProbe
        )
        guard
            let fileSize,
            fileSize > 0,
            let runtimeSeconds,
            runtimeSeconds.isFinite,
            runtimeSeconds > 0,
            resumeSeconds > 0
        else {
            return startupProbeOffset
        }

        let ratio = min(max(resumeSeconds / runtimeSeconds, 0), 0.98)
        let rawOffset = Int64(Double(fileSize) * ratio)
        let resumeOffset = max(0, (rawOffset / alignment) * alignment)
        return max(startupProbeOffset, resumeOffset)
    }

    private static func prefersNonZeroDirectPlayHealthProbe(
        fileSize: Int64?,
        sourceBitrate: Int?,
        rangeLength: Int,
        isTVOS: Bool
    ) -> Bool {
        guard !isTVOS else { return false }
        guard let sourceBitrate, sourceBitrate >= highBitrateDirectPlayThreshold else { return false }
        guard let fileSize else { return false }
        return fileSize >= Int64(rangeLength * 2)
    }

    private static func nonZeroStartupProbeOffset(
        fileSize: Int64?,
        alignment: Int64,
        prefersNonZeroHealthProbe: Bool
    ) -> Int64 {
        guard prefersNonZeroHealthProbe, let fileSize, fileSize > alignment else {
            return 0
        }

        let maxOffset = max(0, fileSize - alignment)
        guard maxOffset >= alignment else { return 0 }
        return alignment
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

        var request = URLRequest(url: PlaybackAuthenticatedRequestURL.forInternalURLSession(requestPlan.url, headers: headers))
        request.timeoutInterval = requestPlan.timeout
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        if let rangeStart = requestPlan.rangeStart {
            let rangeEnd = rangeStart + Int64(max(1, requestPlan.rangeLength)) - 1
            request.setValue("bytes=\(rangeStart)-\(rangeEnd)", forHTTPHeaderField: "Range")
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.network("Startup preheat returned a non-HTTP response.")
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw AppError.network("Startup preheat failed (\(httpResponse.statusCode)).")
        }
        guard httpResponse.statusCode == 206 || requestPlan.rangeStart == nil || requestPlan.rangeStart == 0 else {
            throw AppError.network("Startup preheat ignored a non-zero range request.")
        }

        var data = Data()
        data.reserveCapacity(requestPlan.rangeLength)
        for try await byte in bytes {
            data.append(byte)
            if data.count >= requestPlan.rangeLength {
                break
            }
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

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
