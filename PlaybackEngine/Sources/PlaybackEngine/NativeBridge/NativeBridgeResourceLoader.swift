import Foundation
import AVFoundation
import Shared

/// Integrates the custom demux/repackage pipeline with AVPlayer.
/// AVPlayer uses a custom URL scheme (e.g., `reelfin-bridge://`) which routes
/// all data requests to this delegate. The delegate pulls from the Session.
public final class NativeBridgeResourceLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    
    // MARK: - Types
    
    /// Delegate protocol for the ResourceLoader to request data from the core session.
    public protocol DataSource: Sendable {
        /// Read exactly `length` bytes from the bridged stream starting at `offset`.
        /// Note: This offset is within the *repackaged* (fMP4) stream, not the source MKV.
        func readRepackagedData(offset: Int64, length: Int) async throws -> Data
        
        /// Get the total expected size of the repackaged stream (or a very large estimate
        /// for indefinite streaming).
        func expectedStreamSize() async throws -> Int64
        
        /// Handle a seek request from AVPlayer to a specific byte offset in the fMP4 stream.
        /// The DataSource must map this back to a timestamp, seek the demuxer, and
        /// reset its internal fMP4 byte counter.
        func handleSeek(toByteOffset offset: Int64) async throws

        /// Optional diagnostics hook called when an AVPlayer data request starts.
        func beginResourceRequest(offset: Int64, length: Int) async -> UUID?

        /// Optional diagnostics hook called when an AVPlayer data request ends.
        func endResourceRequest(token: UUID?) async
    }
    
    // MARK: - Properties
    
    public static let customScheme = "reelfin-bridge"
    private let dataSource: DataSource
    private let loaderQueue = DispatchQueue(label: "com.reelfin.NativeBridge.ResourceLoader")
    
    // State management
    private var pendingRequests: [AVAssetResourceLoadingRequest] = []
    private var currentTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    public init(dataSource: DataSource) {
        self.dataSource = dataSource
        super.init()
    }
    
    // MARK: - Public API
    
    /// Prepares an AVURLAsset equipped with this resource loader.
    public func makeAsset(for itemID: String) -> AVURLAsset {
        let encodedItemID = itemID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "invalid-item"
        let urlString = "\(Self.customScheme)://play/\(encodedItemID)"
        let url = URL(string: urlString) ?? URL(string: "\(Self.customScheme)://play/invalid-item")!
        if itemID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) == nil {
            AppLog.nativeBridge.error("Failed to percent-encode item ID for resource loader: \(itemID, privacy: .public)")
        }
        
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(self, queue: loaderQueue)

        // [NB-DIAG] Watchdog: detect if AVPlayer never issues a resource request
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.pendingRequests.isEmpty && self.currentTask == nil {
                AppLog.nativeBridge.warning("[NB-DIAG] ResourceLoader watchdog: no requests received from AVPlayer after 10s — asset may have been rejected")
            }
        }
        loaderQueue.asyncAfter(deadline: .now() + 10, execute: watchdog)

        return asset
    }
    
    public func invalidate() {
        loaderQueue.async {
            self.currentTask?.cancel()
            self.currentTask = nil
            for request in self.pendingRequests {
                if !request.isFinished && !request.isCancelled {
                    request.finishLoading(with: NativeBridgeError.cancelled)
                }
            }
            self.pendingRequests.removeAll()
        }
    }
    
    // MARK: - AVAssetResourceLoaderDelegate
    
    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let url = loadingRequest.request.url, url.scheme == Self.customScheme else {
            return false
        }
        
        let dataReq = loadingRequest.dataRequest
        let offset = dataReq?.requestedOffset ?? -1
        let length = dataReq?.requestedLength ?? -1
        let hasContentInfo = loadingRequest.contentInformationRequest != nil
        AppLog.nativeBridge.notice("[NB-DIAG] ResourceLoader: incoming request offset=\(offset) length=\(length) contentInfo=\(hasContentInfo) pending=\(self.pendingRequests.count)")

        pendingRequests.append(loadingRequest)
        processPendingRequests()
        
        return true
    }
    
    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        pendingRequests.removeAll(where: { $0 == loadingRequest })
    }
    
    // MARK: - Request Processing
    
    private func processPendingRequests() {
        guard currentTask == nil, let request = pendingRequests.first else {
            return
        }
        
        guard let dataRequest = request.dataRequest else {
            request.finishLoading(with: NSError(domain: "NativeBridge", code: -1, userInfo: nil))
            pendingRequests.removeFirst()
            processPendingRequests()
            return
        }
        
        currentTask = Task {
            var requestToken: UUID?
            defer {
                Task {
                    await self.dataSource.endResourceRequest(token: requestToken)
                }
            }
            do {
                if let contentInformationRequest = request.contentInformationRequest {
                    let size = try await dataSource.expectedStreamSize()
                    contentInformationRequest.contentType = "public.mpeg-4"
                    contentInformationRequest.contentLength = size
                    contentInformationRequest.isByteRangeAccessSupported = true
                }
                
                let requestedOffset = dataRequest.requestedOffset
                let requestedLength = dataRequest.requestedLength
                requestToken = await dataSource.beginResourceRequest(
                    offset: requestedOffset,
                    length: requestedLength
                )
                
                AppLog.playback.debug("ResourceLoader: Requested \(requestedLength) bytes at offset \(requestedOffset)")
                
                // Tell data source we might be seeking if this offset is unexpected
                try await dataSource.handleSeek(toByteOffset: requestedOffset)
                
                // Read chunks until the request is fulfilled
                var bytesRead = 0
                var currentOffset = requestedOffset
                
                while bytesRead < requestedLength {
                    if Task.isCancelled || request.isCancelled {
                        break
                    }
                    
                    // Fetch in small internal chunks (e.g., 256KB) to feed AVPlayer steadily
                    let chunkSize = min(256 * 1024, requestedLength - bytesRead)
                    let chunk = try await dataSource.readRepackagedData(offset: currentOffset, length: chunkSize)
                    
                    guard !chunk.isEmpty else {
                        // EOF reached
                        break
                    }
                    
                    dataRequest.respond(with: chunk)
                    bytesRead += chunk.count
                    currentOffset += Int64(chunk.count)
                }
                
                if !Task.isCancelled && !request.isCancelled {
                    request.finishLoading()
                    AppLog.playback.debug("ResourceLoader: Fulfilled \(bytesRead) bytes")
                }
                
            } catch {
                if !Task.isCancelled && !request.isCancelled {
                    AppLog.playback.error("ResourceLoader failed: \(error.localizedDescription, privacy: .public)")
                    request.finishLoading(with: error)
                }
            }
            
            // Clean up and process next
            loaderQueue.async {
                self.currentTask = nil
                self.pendingRequests.removeAll(where: { $0 == request })
                self.processPendingRequests()
            }
        }
    }
}

public extension NativeBridgeResourceLoader.DataSource {
    func beginResourceRequest(offset: Int64, length: Int) async -> UUID? {
        _ = (offset, length)
        return nil
    }

    func endResourceRequest(token: UUID?) async {
        _ = token
    }
}
