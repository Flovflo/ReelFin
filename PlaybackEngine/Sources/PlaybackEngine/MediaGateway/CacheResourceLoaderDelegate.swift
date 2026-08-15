import AVFoundation
import Foundation
import NativeMediaCore
import Shared
import UniformTypeIdentifiers

enum CacheLoaderError: LocalizedError {
    case missingContentLength
    case livenessTimeout(offset: Int64)

    var errorDescription: String? {
        switch self {
        case .missingContentLength:
            return "Cache loader could not determine the origin content length."
        case .livenessTimeout(let offset):
            return "Cache loader saw no coverage progress at offset \(offset) within the liveness deadline."
        }
    }
}

/// Feeds AVPlayer raw original bytes from the `MediaGatewayStore`, never from the network directly.
///
/// Every AVPlayer data request is served from the store: read the contiguous prefix that exists
/// right now, respond with it, and if more is needed wait for the `OriginDownloader` to fill the
/// gap. The serve path NEVER opens a connection — that is the downloader's sole job — so a request
/// being cancelled or a connection dropping can never cut playback: the bytes are already on disk
/// or arriving on the downloader's keep-alive connection.
///
/// Concurrent by construction: one `Task` per loading request (store reads are reentrant), so a
/// cached request is never head-of-line-blocked behind an uncached seek — the bug in the serial
/// `NativeBridgeResourceLoader`.
public final class CacheResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    public static let customScheme = "reelfin-cache"

    private let store: MediaGatewayStore
    private let downloader: OriginDownloader
    private let key: MediaGatewayCacheKey
    private let storageID: String
    private let overrideMIMEType: String?
    private let loaderQueue = DispatchQueue(label: "com.reelfin.CacheResourceLoader")

    private let serveChunk = 4 * 1_024 * 1_024
    private let pollInterval: UInt64 = 40_000_000      // 40 ms
    private let livenessDeadline: TimeInterval = 20

    private let taskRegistry = TokenTaskRegistry<ObjectIdentifier>()
    // Per active request: its current serve offset and whether it is currently STARVED (waiting for
    // bytes that aren't cached yet). The downloader fills the lowest starved offset first (unblock
    // the most-behind request — moov at startup, playback after), and only builds cushion ahead of
    // the furthest request when nothing is starved. This serves both AVPlayer's metadata read and
    // its far-ahead playback request with one connection, in the right order.
    private let playheadState = PlayheadTargetState<ObjectIdentifier>()
    private let playheadPolicy = PlayheadPublicationPolicy()
    private lazy var playheadCoordinator = PlayheadPublicationCoordinator(policy: playheadPolicy) { [downloader] target in
        await downloader.setPlayhead(target)
    }

    init(
        store: MediaGatewayStore,
        downloader: OriginDownloader,
        key: MediaGatewayCacheKey,
        overrideMIMEType: String?
    ) {
        self.store = store
        self.downloader = downloader
        self.key = key
        self.storageID = store.storageIdentifier(for: key)
        self.overrideMIMEType = overrideMIMEType
        super.init()
    }

    /// Builds an `AVURLAsset` whose every request routes to this delegate.
    public func makeAsset(for itemID: String) -> AVURLAsset {
        let encoded = itemID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "item"
        let url = URL(string: "\(Self.customScheme)://play/\(encoded)")
            ?? URL(string: "\(Self.customScheme)://play/item")!
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(self, queue: loaderQueue)
        return asset
    }

    public func invalidate() {
        let inflight = taskRegistry.drain()
        for task in inflight { task.cancel() }
        Task { await downloader.stop() }
    }

    // MARK: - AVAssetResourceLoaderDelegate

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let url = loadingRequest.request.url, url.scheme == Self.customScheme else {
            return false
        }
        let id = ObjectIdentifier(loadingRequest)
        let reservation = taskRegistry.reserve(id)
        let token = reservation.token
        reservation.replacedTask?.cancel()
        let task = Task { [weak self] in
            await self?.handle(loadingRequest)
            self?.removeTask(id, token: token)
        }
        let attached = taskRegistry.attach(task, key: id, token: token)
        if !attached { task.cancel() }
        return true
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        let id = ObjectIdentifier(loadingRequest)
        let task = taskRegistry.removeCurrent(key: id)
        task?.cancel()
        republishPlayhead(removing: id)
    }

    private func removeTask(_ id: ObjectIdentifier, token: UUID) {
        let removal = taskRegistry.remove(key: id, token: token)
        guard removal.removed else { return }
        republishPlayhead(removing: id)
    }

    /// Record this request's offset + starvation state and push the downloader's target: the
    /// lowest starved offset (unblock the most-behind request), or — if none starved — the furthest
    /// active offset (build cushion ahead of playback).
    private func publish(id: ObjectIdentifier, offset: Int64, waiting: Bool) async {
        let publication = playheadState.update(key: id, offset: offset, waiting: waiting)
        await playheadCoordinator.publish(publication)
    }

    /// Drop a finished/cancelled request and re-point the downloader (so a backward seek, after
    /// AVPlayer cancels the old forward request, lowers the target).
    private func republishPlayhead(removing id: ObjectIdentifier) {
        let publication = playheadState.remove(key: id)
        Task { await playheadCoordinator.publish(publication) }
    }

    // MARK: - Serving

    private func handle(_ loadingRequest: AVAssetResourceLoadingRequest) async {
        do {
            if let info = loadingRequest.contentInformationRequest {
                let (length, mime) = await downloader.contentInfo()
                guard let length else { throw CacheLoaderError.missingContentLength }
                info.contentType = Self.uti(forMIME: overrideMIMEType ?? mime)
                info.contentLength = length
                info.isByteRangeAccessSupported = true
            }
            if let dataRequest = loadingRequest.dataRequest {
                try await serve(dataRequest, for: loadingRequest)
            }
            if !loadingRequest.isCancelled && !loadingRequest.isFinished {
                loadingRequest.finishLoading()
            }
        } catch is CancellationError {
            // AVPlayer cancelled the request; nothing to finish. The download keeps running.
        } catch {
            AppLog.playback.warning(
                "playback.cacheloader.serve.fail — item=\(AppLogFormat.correlationIdentifier(self.key.itemID, domain: .media), privacy: .public) reason=\(error.localizedDescription, privacy: .public)"
            )
            if !loadingRequest.isCancelled && !loadingRequest.isFinished {
                loadingRequest.finishLoading(with: error)
            }
        }
    }

    private func serve(
        _ dataRequest: AVAssetResourceLoadingDataRequest,
        for loadingRequest: AVAssetResourceLoadingRequest
    ) async throws {
        let (total, _) = await downloader.contentInfo()
        guard let total else { throw CacheLoaderError.missingContentLength }

        let id = ObjectIdentifier(loadingRequest)
        let startOffset = dataRequest.requestedOffset
        let end: Int64 = dataRequest.requestsAllDataToEndOfResource
            ? total
            : min(total, startOffset + Int64(dataRequest.requestedLength))
        var offset = dataRequest.currentOffset
        var lastProgress = Date()
        var waitedForFill = false

        while offset < end {
            if Task.isCancelled || loadingRequest.isCancelled { return }

            let want = Int(min(Int64(serveChunk), end - offset))
            if want > 0,
               let data = try await store.readAvailablePrefix(from: offset, maxLength: want, key: key),
               !data.isEmpty {
                if waitedForFill {
                    AppLog.playback.notice(
                        "playback.cacheloader.serve.resumed — item=\(AppLogFormat.correlationIdentifier(self.key.itemID, domain: .media), privacy: .public) offsetMB=\(offset / 1_048_576, privacy: .public)"
                    )
                    waitedForFill = false
                }
                dataRequest.respond(with: data)
                offset += Int64(data.count)
                lastProgress = Date()
                // Serving fine — report position so the downloader builds cushion ahead of us.
                await publish(id: id, offset: offset, waiting: false)
                continue
            }

            // The byte at `offset` isn't cached yet — mark this request STARVED so the downloader
            // prioritizes filling here, and wait. The serve path never opens a connection.
            await publish(id: id, offset: offset, waiting: true)
            if !waitedForFill {
                AppLog.playback.warning(
                    "playback.cacheloader.serve.wait — item=\(AppLogFormat.correlationIdentifier(self.key.itemID, domain: .media), privacy: .public) offsetMB=\(offset / 1_048_576, privacy: .public)"
                )
                waitedForFill = true
            }
            if Date().timeIntervalSince(lastProgress) > livenessDeadline {
                throw CacheLoaderError.livenessTimeout(offset: offset)
            }
            try? await Task.sleep(nanoseconds: pollInterval)
        }
    }

    private static func uti(forMIME mime: String?) -> String {
        if let mime, let type = UTType(mimeType: mime)?.identifier {
            return type
        }
        return UTType.mpeg4Movie.identifier
    }
}
