import Foundation
import NativeMediaCore
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
            sourceIsHDRorDV: selection.source.isLikelyHDRorDV,
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
            // Cancellation is NOT a connection verdict (playback proceeded / a newer probe replaced
            // this one) — return nil so the decision stays optimistic.
            return nil
        } catch where isConnectionFailure(error) {
            // A genuine CONNECTION failure (timeout -1001, reset -1005, can't-connect) on a route
            // that REQUIRED this preheat means the link couldn't deliver even the small warming probe
            // — it cannot sustain a high-bitrate / Dolby Vision direct play right now. Return a
            // ZERO-throughput result (not nil) so the startup decision BLOCKS direct play (headroom
            // ≤ 0 → .directPlayPreflightInsufficient) and routes to the watchable SDR transcode from
            // the start, instead of nil → guardedDecision → starting DV that stalls ~6-12s then cuts.
            // (Low-bitrate / SDR sources never reach this effect: their decision returns `fast`
            // before consulting the preheat result.)
            let elapsed = max(0.001, Date().timeIntervalSince(startedAt))
            AppLog.playback.notice(
                "playback.startup.preheat.failed — item=\(selection.source.itemID.prefix(8), privacy: .public) reason=\(requestPlan.reason, privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 3)) error=\(error.localizedDescription, privacy: .public) action=route_watchable_sdr"
            )
            return Result(
                byteCount: 0,
                elapsedSeconds: elapsed,
                observedBitrate: 0,
                rangeStart: requestPlan.rangeStart,
                reason: requestPlan.reason + "_failed"
            )
        } catch {
            // Any OTHER error (non-2xx status, a server that ignores range requests, etc.) is a
            // capability/protocol issue, not a connection-speed verdict — keep the prior behavior
            // (nil → the decision falls back to its guarded default).
            AppLog.playback.debug(
                "playback.startup.preheat.skipped — item=\(selection.source.itemID.prefix(8), privacy: .public) reason=\(requestPlan.reason, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// True for genuine network/connection failures that mean the link cannot carry a high-bitrate
    /// direct play right now (so the startup decision should route to a watchable lower-bitrate
    /// transcode rather than start direct play that will stall). Excludes cancellation and HTTP
    /// capability errors.
    private static func isConnectionFailure(_ error: Error) -> Bool {
        let connectionFailureCodes: Set<Int> = [
            NSURLErrorTimedOut,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorCannotFindHost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorSecureConnectionFailed,
            NSURLErrorResourceUnavailable
        ]
        if let urlError = error as? URLError, connectionFailureCodes.contains(urlError.errorCode) {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && connectionFailureCodes.contains(nsError.code)
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
                sourceIsHDRorDV: selection.source.isLikelyHDRorDV,
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
                    sourceIsHDRorDV: selection.source.isLikelyHDRorDV,
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
        sourceIsHDRorDV: Bool,
        isTVOS: Bool
    ) -> Int {
        let baseLength = isTVOS ? 4 * mebibyte : 2 * mebibyte
        if sourceIsHDRorDV, !isTVOS {
            // Connection-warming + throughput probe only — NOT a playback-buffer fill (AVPlayer
            // fills its own forward buffer). A large 12 MB probe on a 26 Mbps DV original needs
            // ~24 Mbps sustained inside the 4 s timeout; on a link that momentarily dips it times
            // out (-1001) and adds ~4 s of dead startup latency. A small probe reliably completes
            // (4 MB / 4 s = 8 Mbps) and still warms the TLS connection + measures throughput.
            return 4 * mebibyte
        }
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
        sourceIsHDRorDV: Bool,
        rangeLength: Int,
        isTVOS: Bool
    ) -> Bool {
        guard !isTVOS else { return false }
        let needsNonZeroProbe = sourceIsHDRorDV || (sourceBitrate ?? 0) >= highBitrateDirectPlayThreshold
        guard needsNonZeroProbe else { return false }
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
        // This probe is part of the media-origin hot path. Keep CFNetwork's shared protocol state
        // so a tvOS device that already rejected this origin's QUIC route goes straight to H2.
        let configuration = MediaOriginTransport.makeConfiguration()
        configuration.timeoutIntervalForRequest = requestPlan.timeout
        configuration.timeoutIntervalForResource = requestPlan.timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 2
        if let urlProtocolClasses {
            configuration.protocolClasses = urlProtocolClasses + (configuration.protocolClasses ?? [])
        }
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

        // Bulk chunked read so the measured throughput reflects the network, not the cost of
        // byte-by-byte AsyncBytes iteration (which capped the measurement around 8 MB/s and
        // pushed startup into guarded mode unnecessarily).
        let (data, httpResponse) = try await HTTPChunkedRangeReader.collect(
            request: request,
            configuration: configuration,
            maxLength: requestPlan.rangeLength
        )
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw AppError.network("Startup preheat failed (\(httpResponse.statusCode)).")
        }
        guard httpResponse.statusCode == 206 || requestPlan.rangeStart == nil || requestPlan.rangeStart == 0 else {
            throw AppError.network("Startup preheat ignored a non-zero range request.")
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

        // The byte-source path surfaces cancellation as MediaAccessError — misreading it as a
        // generic failure logged a scary "preheat.skipped" for what is a normal press-time cancel.
        if case MediaAccessError.cancelled = error {
            return true
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
