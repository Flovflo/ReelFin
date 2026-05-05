import Foundation
import Shared

public enum PlaybackServerNetworkBaseline {
    private static let mebibyte = 1_024 * 1_024
    static let maximumAge: TimeInterval = 60
    public static let defaultNetworkScope = "default"

    public struct Result: Sendable, Equatable {
        public let byteCount: Int
        public let elapsedSeconds: Double
        public let observedBitrate: Double
        public let createdAt: Date
        public let serverKey: String
        public let networkScope: String

        public init(
            byteCount: Int,
            elapsedSeconds: Double,
            observedBitrate: Double,
            createdAt: Date,
            serverKey: String,
            networkScope: String
        ) {
            self.byteCount = byteCount
            self.elapsedSeconds = elapsedSeconds
            self.observedBitrate = observedBitrate
            self.createdAt = createdAt
            self.serverKey = serverKey
            self.networkScope = networkScope
        }

        func isFresh(at now: Date, maximumAge: TimeInterval = PlaybackServerNetworkBaseline.maximumAge) -> Bool {
            now.timeIntervalSince(createdAt) <= maximumAge
        }
    }

    public static func serverKey(for url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? "https"
        let host = url.host?.lowercased() ?? "unknown"
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    static func isEligible(selection: PlaybackAssetSelection) -> Bool {
        guard !isLocalURL(selection.assetURL) else { return false }
        guard case let .directPlay(url) = selection.decision.route else { return false }
        return !isPlaylistURL(url)
    }

    static func warm(
        selection: PlaybackAssetSelection,
        isTVOS: Bool,
        urlProtocolClasses: [AnyClass]? = nil,
        now: Date = Date()
    ) async -> Result? {
        guard isEligible(selection: selection) else { return nil }
        let plannedBytes = isTVOS ? 8 * mebibyte : 4 * mebibyte
        let timeout: TimeInterval = isTVOS ? 2.5 : 2
        let startedAt = Date()

        do {
            let data = try await fetch(
                url: selection.assetURL,
                headers: selection.headers,
                byteCount: plannedBytes,
                timeout: timeout,
                urlProtocolClasses: urlProtocolClasses
            )
            let elapsed = max(0.001, Date().timeIntervalSince(startedAt))
            let result = Result(
                byteCount: data.count,
                elapsedSeconds: elapsed,
                observedBitrate: Double(data.count * 8) / elapsed,
                createdAt: now,
                serverKey: serverKey(for: selection.assetURL),
                networkScope: defaultNetworkScope
            )
            AppLog.playback.info(
                "playback.server_baseline.done — item=\(selection.source.itemID.prefix(8), privacy: .public) bytes=\(result.byteCount, privacy: .public) elapsed=\(result.elapsedSeconds, format: .fixed(precision: 3)) bitrate=\(Int(result.observedBitrate), privacy: .public)"
            )
            return result
        } catch where isCancellation(error) {
            return nil
        } catch {
            AppLog.playback.debug(
                "playback.server_baseline.skipped — item=\(selection.source.itemID.prefix(8), privacy: .public) errorType=\(String(describing: type(of: error)), privacy: .public)"
            )
            return nil
        }
    }

    private static func fetch(
        url: URL,
        headers: [String: String],
        byteCount: Int,
        timeout: TimeInterval,
        urlProtocolClasses: [AnyClass]?
    ) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 2
        if let urlProtocolClasses {
            configuration.protocolClasses = urlProtocolClasses + (configuration.protocolClasses ?? [])
        }
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: PlaybackAuthenticatedRequestURL.forInternalURLSession(url, headers: headers))
        request.timeoutInterval = timeout
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("bytes=0-\(byteCount - 1)", forHTTPHeaderField: "Range")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.network("Server baseline returned a non-HTTP response.")
        }
        guard httpResponse.statusCode == 206 else {
            throw AppError.network("Server baseline failed (\(httpResponse.statusCode)).")
        }

        var data = Data()
        data.reserveCapacity(byteCount)
        for try await byte in bytes {
            data.append(byte)
            if data.count >= byteCount {
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
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
