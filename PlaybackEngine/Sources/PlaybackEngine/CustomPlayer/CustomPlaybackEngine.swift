import AVFoundation
import Foundation
import NativeMediaCore
import Observation
import Shared

/// The original source for a title, resolved from Jellyfin — the minimal input the custom engine
/// needs to play it through the local cache. (A thin adapter over `PlaybackCoordinator` provides
/// this in the app; tests provide a mock, so the engine is offline-testable.)
public struct ResolvedOriginalSource: Sendable {
    public let originURL: URL
    public let headers: [String: String]
    /// Original bitrate in bits/s (drives every dynamic, per-file decision). nil ⇒ assume high.
    public let sourceBitrate: Int?
    public let overrideMIMEType: String?
    public let cacheKey: MediaGatewayCacheKey
    public let isDolbyVision: Bool

    public init(originURL: URL, headers: [String: String], sourceBitrate: Int?, overrideMIMEType: String?, cacheKey: MediaGatewayCacheKey, isDolbyVision: Bool) {
        self.originURL = originURL
        self.headers = headers
        self.sourceBitrate = sourceBitrate
        self.overrideMIMEType = overrideMIMEType
        self.cacheKey = cacheKey
        self.isDolbyVision = isDolbyVision
    }
}

public protocol CustomPlaybackSourceResolving: Sendable {
    func resolveOriginal(itemID: String, startTimeTicks: Int64?) async throws -> ResolvedOriginalSource
}

/// The clean custom player (blueprint §2). ONE `AVPlayer`, fed the original bytes from the local
/// disk cache over `http://127.0.0.1` (DV-safe), with the ORIGINAL-FIRST dynamic brain driving a
/// loading bar instead of cuts or quality drops. The cache's own fill rate is the connection probe
/// (no separate preheat). Composes the four offline-tested cores; no legacy coordinator/guard/
/// sample-buffer/NativeBridge cruft.
@MainActor
@Observable
public final class CustomPlaybackEngine {
    public let player: AVPlayer
    public private(set) var bufferingState: PlaybackBufferingState = .idle
    public private(set) var errorMessage: String?

    /// Default deep-cache budget (4 GB iOS / 10 GB tvOS). Public so the app can size the store it
    /// passes in to match the engine's read-ahead budget.
    public static var defaultCacheBudgetBytes: Int64 { CacheProxySession.defaultCacheBudgetBytes }

    private let resolver: CustomPlaybackSourceResolving
    private let store: MediaGatewayStore

    private var session: CacheProxySession?
    private var monitor: ConnectionMonitor?
    private var sourceBitrateMbps: Double = 30
    private var loadTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var stalledObserver: NSObjectProtocol?
    private var audioInterruptionObserver: NSObjectProtocol?

    private let probeWindow: TimeInterval = 1.5
    private let monitorInterval: UInt64 = 1_000_000_000 // 1s

    public init(resolver: CustomPlaybackSourceResolving, store: MediaGatewayStore) {
        self.resolver = resolver
        self.store = store
        self.player = AVPlayer()
        self.player.automaticallyWaitsToMinimizeStalling = true
    }

    /// Route audio to playback (movie) so there IS sound — and it ignores the silent switch, like a
    /// video player should. Run off the main thread (AVAudioSession.setActive is synchronous/blocking).
    private static func configureAudioSessionForPlayback() {
#if os(iOS)
        DispatchQueue.global(qos: .userInitiated).async {
            let session = AVAudioSession.sharedInstance()
            do {
#if targetEnvironment(simulator)
                try session.setCategory(.playback)
#else
                try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
#endif
                try session.setActive(true)
            } catch {
                do {
                    try session.setCategory(.playback)
                    try session.setActive(true)
                } catch {
                    AppLog.playback.warning("customplayer.audioSession.failed — \(error.localizedDescription, privacy: .public)")
                }
            }
        }
#endif
    }

    // MARK: - Public control

    public func load(itemID: String, startTimeTicks: Int64? = nil, autoPlay: Bool = true) {
        teardown()
        bufferingState = PlaybackBufferingState(phase: .prebuffering)
        errorMessage = nil
        loadTask = Task { [weak self] in
            await self?.runLoad(itemID: itemID, startTimeTicks: startTimeTicks, autoPlay: autoPlay)
        }
    }

    public func play() { player.play() }
    public func pause() { player.pause() }

    public func seek(toSeconds seconds: Double) {
        session?.setPlayheadOffset(session?.byteOffset(forSeconds: seconds) ?? 0)
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600))
    }

    public func stop() {
        teardown()
        bufferingState = .idle
    }

    // MARK: - Load flow

    private func runLoad(itemID: String, startTimeTicks: Int64?, autoPlay: Bool) async {
        let resolved: ResolvedOriginalSource
        do {
            resolved = try await resolver.resolveOriginal(itemID: itemID, startTimeTicks: startTimeTicks)
        } catch {
            errorMessage = "Impossible de résoudre la source : \(error.localizedDescription)"
            bufferingState = .idle
            return
        }
        guard !Task.isCancelled else { return }

        Self.configureAudioSessionForPlayback()
        observeAudioInterruptions()
        sourceBitrateMbps = Double(resolved.sourceBitrate ?? 30_000_000) / 1_000_000
        monitor = ConnectionMonitor(sourceBitrateMbps: sourceBitrateMbps)

        let session = CacheProxySession(
            originURL: resolved.originURL, headers: resolved.headers, key: resolved.cacheKey,
            store: store, sourceBitrate: resolved.sourceBitrate, overrideMIMEType: resolved.overrideMIMEType)
        let localURL: URL
        do {
            localURL = try session.start()
        } catch {
            errorMessage = "Cache local indisponible : \(error.localizedDescription)"
            bufferingState = .idle
            return
        }
        self.session = session

        let startSeconds = Double(startTimeTicks ?? 0) / 10_000_000
        var options: [String: Any] = [:]
        if let mime = resolved.overrideMIMEType { options[AVURLAssetOverrideMIMETypeKey] = mime }
        let asset = AVURLAsset(url: localURL, options: options)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 0 // fast first frame; reservoir lives on disk
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        player.replaceCurrentItem(with: item)
        if startSeconds > 0 {
            session.setPlayheadOffset(session.byteOffset(forSeconds: startSeconds))
        }
        observeStalls(for: item)

        await runStartup(startSeconds: startSeconds, autoPlay: autoPlay)
        startMonitorLoop(startSeconds: startSeconds)
    }

    /// The cache's fill rate is the connection probe: seconds-of-content gained per wall-second ≈
    /// throughput headroom. Decide play-now vs pre-buffer-behind-the-loading-bar, dynamically.
    private func runStartup(startSeconds: Double, autoPlay: Bool) async {
        guard let session else { return }
        let r1 = await session.reservoirSecondsAhead(atSeconds: startSeconds)
        try? await Task.sleep(nanoseconds: UInt64(probeWindow * 1_000_000_000))
        guard !Task.isCancelled else { return }
        let r2 = await session.reservoirSecondsAhead(atSeconds: startSeconds)
        let headroom = max(0, (r2 - r1) / probeWindow)
        let measuredMbps = headroom * sourceBitrateMbps
        monitor?.record(mbps: measuredMbps, at: Date())

        let action = PlaybackLanePolicy.startupAction(
            measuredMbps: measuredMbps > 0 ? measuredMbps : nil,
            sourceBitrateMbps: sourceBitrateMbps,
            reservoirSecondsAlready: r2)
        bufferingState = .fromStartup(action, reservoirSeconds: r2)

        if case let .prebufferOriginal(target) = action {
            // Build the original cushion behind the loading bar before first play.
            let deadline = Date().addingTimeInterval(40)
            while !Task.isCancelled, Date() < deadline {
                let depth = await session.reservoirSecondsAhead(atSeconds: startSeconds)
                bufferingState = PlaybackBufferingState(phase: .prebuffering, reservoirSeconds: depth, targetSeconds: target)
                if depth >= target { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        guard !Task.isCancelled else { return }
        let depth = await session.reservoirSecondsAhead(atSeconds: startSeconds)
        bufferingState = PlaybackBufferingState(phase: .playing, reservoirSeconds: depth)
        if autoPlay { player.play() }
    }

    // MARK: - Steady monitor (loading bar + keep-original / last-resort decisions)

    private func startMonitorLoop(startSeconds: Double) {
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self?.monitorInterval ?? 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await self.monitorTick()
            }
        }
    }

    private func monitorTick() async {
        guard let session, player.currentItem != nil else { return }
        let nowSeconds = player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0
        // Cache depth for the HUD only — this is a CBR byte↔seconds estimate, fine to *display* but
        // NOT to gate buffering on (it oscillates on a VBR file).
        let reservoir = await session.reservoirSecondsAhead(atSeconds: nowSeconds)
        // The localhost server already publishes AVPlayer's REAL read offset to the downloader, so we
        // do NOT push a CBR-estimated playhead here — that fought the accurate, request-driven one.

        // Drive the loading bar from AVPlayer's REAL transport state, not the byte estimate. The
        // estimate dipped below threshold periodically on the VBR original and flashed "buffering"
        // every ~10s even while playback was perfectly smooth. Only a genuine stall (AVPlayer has run
        // dry and is waiting for data) shows the bar now.
        switch player.timeControlStatus {
        case .waitingToPlayAtSpecifiedRate:
            bufferingState = PlaybackBufferingState(
                phase: .buffering, reservoirSeconds: reservoir, targetSeconds: PlaybackLanePolicy.bufferResumeSeconds)
        default:
            bufferingState = PlaybackBufferingState(phase: .playing, reservoirSeconds: reservoir)
        }
    }

    // MARK: - Stall observation (reload-averse: just reflect buffering, never rebuild the item)

    /// If the audio session gets interrupted (a call, Siri, another app), reactivate it and resume
    /// so sound comes back — otherwise the picture keeps playing silently (the "lost sound" symptom).
    private func observeAudioInterruptions() {
#if os(iOS)
        if let observer = audioInterruptionObserver { NotificationCenter.default.removeObserver(observer) }
        audioInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let info = note.userInfo,
                  let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended
            else { return }
            Self.configureAudioSessionForPlayback()
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init(rawValue:))
            if options?.contains(.shouldResume) ?? true { self.player.play() }
        }
#endif
    }

    private func observeStalls(for item: AVPlayerItem) {
        if let stalledObserver { NotificationCenter.default.removeObserver(stalledObserver) }
        stalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.monitorTick() }
        }
    }

    // MARK: - Teardown

    private func teardown() {
        loadTask?.cancel(); loadTask = nil
        monitorTask?.cancel(); monitorTask = nil
        if let observer = stalledObserver { NotificationCenter.default.removeObserver(observer) }
        stalledObserver = nil
        if let observer = audioInterruptionObserver { NotificationCenter.default.removeObserver(observer) }
        audioInterruptionObserver = nil
        session?.stop(); session = nil
        monitor = nil
        player.replaceCurrentItem(with: nil)
    }
}
