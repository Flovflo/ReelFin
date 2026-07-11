import AVFoundation
import AVKit
import NativeMediaCore
import Shared
import SwiftUI
import UIKit

struct NativeMatroskaSampleBufferPlayerView: UIViewControllerRepresentable {
    let url: URL
    let headers: [String: String]
    let container: ContainerFormat
    let startTimeSeconds: Double
    let seekRequest: NativePlayerSeekRequest?
    let selectedAudioTrackID: String?
    let selectedSubtitleTrackID: String?
    let baseDiagnostics: [String]
    @Binding var isPaused: Bool
    let onDiagnostics: ([String]) -> Void
    let onPlaybackTime: (Double) -> Void

    func makeUIViewController(context: Context) -> NativeMatroskaSampleBufferPlayerController {
        let controller = NativeMatroskaSampleBufferPlayerController()
        controller.configure(
            url: url,
            headers: headers,
            container: container,
            startTimeSeconds: startTimeSeconds,
            seekRequest: seekRequest,
            selectedAudioTrackID: selectedAudioTrackID,
            selectedSubtitleTrackID: selectedSubtitleTrackID,
            baseDiagnostics: baseDiagnostics,
            isPaused: isPaused,
            onDiagnostics: onDiagnostics,
            onPlaybackTime: onPlaybackTime
        )
        return controller
    }

    func updateUIViewController(_ controller: NativeMatroskaSampleBufferPlayerController, context: Context) {
        controller.configure(
            url: url,
            headers: headers,
            container: container,
            startTimeSeconds: startTimeSeconds,
            seekRequest: seekRequest,
            selectedAudioTrackID: selectedAudioTrackID,
            selectedSubtitleTrackID: selectedSubtitleTrackID,
            baseDiagnostics: baseDiagnostics,
            isPaused: isPaused,
            onDiagnostics: onDiagnostics,
            onPlaybackTime: onPlaybackTime
        )
    }

    static func dismantleUIViewController(_ controller: NativeMatroskaSampleBufferPlayerController, coordinator: ()) {
        controller.stopForDismantle()
    }
}

struct NativeMatroskaForwardSeekState {
    let targetSeconds: Double
    private var videoDecodeStarted = false

    init(targetSeconds: Double) {
        self.targetSeconds = targetSeconds
    }

    mutating func shouldSkip(
        _ packet: MediaPacket,
        videoTrackID: Int,
        audioTrackID: Int?,
        subtitleTrackID: Int?
    ) -> Bool {
        let pts = packet.timestamp.pts.matroskaSafeSeconds
        if packet.trackID == videoTrackID {
            return shouldSkipVideoPacket(packet, pts: pts)
        }
        if let audioTrackID, packet.trackID == audioTrackID {
            return pts < targetSeconds - 0.020
        }
        if let subtitleTrackID, packet.trackID == subtitleTrackID {
            return pts < targetSeconds
        }
        return false
    }

    private mutating func shouldSkipVideoPacket(_ packet: MediaPacket, pts: Double) -> Bool {
        if videoDecodeStarted { return false }
        let prerollStart = max(0, targetSeconds - 2.5)
        guard packet.isKeyframe, pts >= prerollStart else {
            return true
        }
        videoDecodeStarted = true
        return false
    }
}

struct NativePlayerSeekCommitPolicy {
    struct RestartCommit: Equatable {
        let generation: Int
        let targetSeconds: Double
    }

    private(set) var generation = 0
    private(set) var pendingRestart: RestartCommit?
    private(set) var isRestartInFlight = false

    @discardableResult
    mutating func enqueueRestart(targetSeconds: Double) -> Bool {
        generation += 1
        pendingRestart = RestartCommit(
            generation: generation,
            targetSeconds: max(0, targetSeconds)
        )
        let shouldStartCoordinator = !isRestartInFlight
        isRestartInFlight = true
        return shouldStartCoordinator
    }

    mutating func takePendingRestart() -> RestartCommit? {
        defer { pendingRestart = nil }
        return pendingRestart
    }

    mutating func finishRestart() {
        isRestartInFlight = false
    }

    mutating func cancelAll() {
        generation += 1
        pendingRestart = nil
        isRestartInFlight = false
    }

    func ownsCallbacks(from generation: Int) -> Bool {
        self.generation == generation
    }
}

private struct NativeMatroskaRestartConfiguration {
    let generation: Int
    let url: URL
    let headers: [String: String]
    let container: ContainerFormat
    let targetSeconds: Double
    let selectedAudioTrackID: String?
    let selectedSubtitleTrackID: String?
    let isPaused: Bool
}

private final class NativeMatroskaActiveByteSource {
    let generation: Int
    let source: any MediaByteSource
    var cancellationTask: Task<Void, Never>?
    var cancellationCompleted = false

    init(generation: Int, source: any MediaByteSource) {
        self.generation = generation
        self.source = source
    }
}

enum NativeMatroskaTeardownEvent: Equatable {
    case generationInvalidated
    case sourceCancelled
    case readerFinished
    case videoQueueQuiesced
    case audioQueueQuiesced
    case renderersFlushed
}

final class NativeMatroskaSampleBufferPlayerController: UIViewController {
    private let byteSourceFactory: NativeMatroskaByteSourceFactory
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let audioRenderer = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let subtitleOverlay = NativeSubtitleOverlayView()
    private let videoQueue = DispatchQueue(label: "reelfin.nativeplayer.mkv.video", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "reelfin.nativeplayer.mkv.audio", qos: .userInitiated)
    private let renderQueueKey = DispatchSpecificKey<String>()
    private let metricsLock = NSLock()
    private let playbackStateLock = NSLock()
    private let generationLock = NSLock()
    private let bufferPolicy = NativePlaybackBufferPolicy.matroska
    private let videoSamples = NativeSampleBufferQueue(capacity: 180)
    private let audioSamples = NativeSampleBufferQueue(capacity: 320)
    private var audioStarvationGate = NativeAudioStarvationGate(minimumStarvationDuration: 0.75)

    private var currentURL: URL?
    private var currentHeaders: [String: String] = [:]
    private var currentContainer: ContainerFormat = .matroska
    private var currentStartTimeSeconds: Double = 0
    private var currentSelectedAudioTrackID: String?
    private var currentSelectedSubtitleTrackID: String?
    private var appliedSeekRequestID: Int?
    private var pendingForwardSeekRequest: NativePlayerSeekRequest?
    private var baseDiagnostics: [String] = []
    private var onDiagnostics: (([String]) -> Void)?
    private var onPlaybackTime: ((Double) -> Void)?
    private var playbackTask: Task<Void, Never>?
    private var retirementTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var pendingRestartConfiguration: NativeMatroskaRestartConfiguration?
    private var seekCommitPolicy = NativePlayerSeekCommitPolicy()
    private var readerGeneration = NativeMatroskaPlaybackGeneration()
    private var invalidatedCallbackGenerations: Set<Int> = []
    private var activeByteSource: NativeMatroskaActiveByteSource?
    private var activeReaderCount = 0
    private var cancelledSourceGenerations: Set<Int> = []
    private var recordedSourceCancellationGenerations: Set<Int> = []
    private var restartCoordinatorID = 0
    private var retirementCoordinatorID = 0
    private var diagnosticTimer: Timer?
    private var metrics = NativeMatroskaSampleBufferMetrics()
    private var subtitleCues: [SubtitleCue] = []
    private var subtitleClock = SubtitleClockAdapter()
    private var pendingPause = false
    private var playbackCanRun = false
    private var hasAudioTrackForBuffering = false
    private var rebufferingForAudio = false
    private var consecutiveAudioStarvationTicks = 0
    private var reportedAudioStarvation = false
    private var audioTimingNormalizer = NativeAudioTimingNormalizer()
    private var videoDrainTimer: DispatchSourceTimer?
    private var pauseStateGate = NativePauseStateGate()
    private var audioStartupWatchdog = NativeAudioStartupWatchdog()
    private var lastBufferWaitLogTime: TimeInterval = 0
    private var audioRendererFailureReported = false
    private var audioStartupDegraded = false
    private var isTornDown = false
    private var videoHDRMetadata: HDRMetadata?
#if os(tvOS)
    private lazy var displayCriteriaCoordinator = NativeDisplayCriteriaCoordinator(viewController: self)
#endif
    private(set) var playbackGeneration = 0
    private(set) var pauseStateApplicationCount = 0
    private(set) var forwardSeekRequestCount = 0
    private(set) var restartCoordinatorStartCount = 0
    private(set) var maximumConcurrentReaderCount = 0
    private(set) var callbackCountAfterDismantle = 0
    private(set) var teardownEvents: [NativeMatroskaTeardownEvent] = []
    var teardownEventObserver: ((NativeMatroskaTeardownEvent) -> Void)?
    var beforePlaybackTaskCancellation: (() async -> Void)?
    var readerPhase: NativeMatroskaPlaybackGeneration.Phase {
        generationLock.withLock { readerGeneration.phase }
    }
    var readerCanSeekInPlace: Bool {
        generationLock.withLock { readerGeneration.canSeekInPlace }
    }
    var readerOwnsCurrentCallbacks: Bool {
        generationLock.withLock { readerGeneration.owns(readerGeneration.id) }
    }
    var pendingRestartTargetSeconds: Double? { pendingRestartConfiguration?.targetSeconds }
    var pendingRestartIsPaused: Bool { pendingRestartConfiguration?.isPaused ?? pendingPause }
    var pendingRestartSelectedAudioTrackID: String? { pendingRestartConfiguration?.selectedAudioTrackID }
    var pendingRestartSelectedSubtitleTrackID: String? { pendingRestartConfiguration?.selectedSubtitleTrackID }

    init(byteSourceFactory: @escaping NativeMatroskaByteSourceFactory = {
        HTTPRangeByteSource(url: $0, headers: $1)
    }) {
        self.byteSourceFactory = byteSourceFactory
        super.init(nibName: nil, bundle: nil)
        videoQueue.setSpecific(key: renderQueueKey, value: "video")
        audioQueue.setSpecific(key: renderQueueKey, value: "audio")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
        view.layer.addSublayer(displayLayer)
        subtitleOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitleOverlay)
        NSLayoutConstraint.activate([
            subtitleOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            subtitleOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            subtitleOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            subtitleOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        synchronizer.addRenderer(displayLayer)
        synchronizer.addRenderer(audioRenderer)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        displayLayer.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        resetPreferredDisplayCriteria()
        stopPlayback()
    }

    deinit {
        resetPreferredDisplayCriteria()
    }

    func stopForDismantle() {
        isTornDown = true
        stopPlayback(publishFinalPlaybackTime: false)
    }

    func configure(
        url: URL,
        headers: [String: String],
        container: ContainerFormat,
        startTimeSeconds: Double,
        seekRequest: NativePlayerSeekRequest?,
        selectedAudioTrackID: String?,
        selectedSubtitleTrackID: String?,
        baseDiagnostics: [String],
        isPaused: Bool,
        onDiagnostics: @escaping ([String]) -> Void,
        onPlaybackTime: @escaping (Double) -> Void
    ) {
        self.baseDiagnostics = baseDiagnostics
        self.onDiagnostics = onDiagnostics
        self.onPlaybackTime = onPlaybackTime
        pendingPause = isPaused
        isTornDown = false
        let sourceChanged = currentURL != url || currentHeaders != headers || currentContainer != container
        let selectionChanged = currentSelectedAudioTrackID != selectedAudioTrackID
            || currentSelectedSubtitleTrackID != selectedSubtitleTrackID
        currentSelectedAudioTrackID = selectedAudioTrackID
        currentSelectedSubtitleTrackID = selectedSubtitleTrackID
        if sourceChanged {
            currentURL = url
            currentHeaders = headers
            currentContainer = container
            currentStartTimeSeconds = startTimeSeconds
            appliedSeekRequestID = seekRequest?.id
            startPlayback(url: url, headers: headers, container: container, startTimeSeconds: startTimeSeconds, selectedAudioTrackID: selectedAudioTrackID, selectedSubtitleTrackID: selectedSubtitleTrackID)
        } else if let seekRequest, appliedSeekRequestID != seekRequest.id {
            handleSeekRequest(seekRequest, url: url, headers: headers, container: container, selectedAudioTrackID: selectedAudioTrackID, selectedSubtitleTrackID: selectedSubtitleTrackID)
        } else if selectionChanged {
            startPlayback(url: url, headers: headers, container: container, startTimeSeconds: currentPlaybackSecondsForRestart(), selectedAudioTrackID: selectedAudioTrackID, selectedSubtitleTrackID: selectedSubtitleTrackID)
        }
        setPaused(isPaused)
        publishDiagnostics(generation: currentReaderGeneration)
    }

    private func beginReaderStart() -> Int {
        generationLock.withLock { readerGeneration.beginStart() }
    }

    private func markReaderActive(_ candidate: Int) {
        generationLock.withLock { readerGeneration.markActive(candidate) }
    }

    private func beginReaderRetirement() -> Int? {
        generationLock.withLock {
            guard readerGeneration.phase != .idle else { return nil }
            readerGeneration.beginRetirement()
            return readerGeneration.id
        }
    }

    private func invalidateCallbackOwnership(for generation: Int) {
        let inserted = generationLock.withLock {
            invalidatedCallbackGenerations.insert(generation).inserted
        }
        if inserted {
            recordTeardownEvent(.generationInvalidated)
        }
    }

    private func finishReaderRetirement(_ candidate: Int) {
        generationLock.withLock {
            readerGeneration.finishRetirement(candidate)
            invalidatedCallbackGenerations.remove(candidate)
        }
    }

    private func finishReaderAfterCompletion(_ candidate: Int) {
        generationLock.withLock {
            guard readerGeneration.owns(candidate) else { return }
            readerGeneration.beginRetirement()
        }
    }

    private func ownsCallbacks(from generation: Int) -> Bool {
        generationLock.withLock {
            readerGeneration.owns(generation) && !invalidatedCallbackGenerations.contains(generation)
        }
    }

    private var currentReaderGeneration: Int {
        generationLock.withLock { readerGeneration.id }
    }

    private func currentPlaybackSecondsForRestart() -> Double {
        let seconds = synchronizer.currentTime().matroskaSafeSeconds
        return seconds.isFinite ? max(0, seconds) : max(0, currentStartTimeSeconds)
    }

    private func handleSeekRequest(
        _ seekRequest: NativePlayerSeekRequest,
        url: URL,
        headers: [String: String],
        container: ContainerFormat,
        selectedAudioTrackID: String?,
        selectedSubtitleTrackID: String?
    ) {
        appliedSeekRequestID = seekRequest.id
        if canApplyForwardSeek(to: seekRequest.targetSeconds) {
            requestForwardSeek(seekRequest)
        } else {
            startPlayback(
                url: url,
                headers: headers,
                container: container,
                startTimeSeconds: seekRequest.targetSeconds,
                selectedAudioTrackID: selectedAudioTrackID,
                selectedSubtitleTrackID: selectedSubtitleTrackID
            )
        }
    }

    private func canApplyForwardSeek(to targetSeconds: Double) -> Bool {
        guard readerCanSeekInPlace else { return false }
        return targetSeconds + 0.5 >= currentPlaybackSecondsForRestart()
    }

    private func requestForwardSeek(_ request: NativePlayerSeekRequest) {
        forwardSeekRequestCount += 1
        currentStartTimeSeconds = request.targetSeconds
        playbackStateLock.lock()
        pendingForwardSeekRequest = request
        playbackCanRun = false
        rebufferingForAudio = false
        consecutiveAudioStarvationTicks = 0
        reportedAudioStarvation = false
        lastBufferWaitLogTime = 0
        audioRendererFailureReported = false
        audioStartupDegraded = false
        audioStartupWatchdog.reset()
        audioStarvationGate.reset()
        let hasAudio = hasAudioTrackForBuffering
        playbackStateLock.unlock()

        audioTimingNormalizer.reset()
        pauseStateGate.reset()
        subtitleCues.removeAll()
        videoSamples.removeAll()
        audioSamples.removeAll()
        stopDrainTimers()
        displayLayer.flushAndRemoveImage()
        audioRenderer.flush()
        resetMetricsForSeek(targetSeconds: request.targetSeconds, hasAudio: hasAudio)
        startClock(at: request.targetSeconds, paused: true)
        startDrainTimers(generation: currentReaderGeneration)
        AppLog.playback.notice("nativeplayer.seek.forward_in_place — target=\(request.targetSeconds, privacy: .public)")
    }

    private func resetMetricsForSeek(targetSeconds: Double, hasAudio: Bool) {
        metricsLock.lock()
        metrics = NativeMatroskaSampleBufferMetrics()
        metrics.state = "buffering"
        metrics.startTime = targetSeconds
        metrics.videoDecoderBackend = "VideoToolbox"
        metrics.audioDecoderBackend = hasAudio ? "AppleAudioToolbox" : "none"
        applyHDRMetrics(from: videoHDRMetadata)
        metricsLock.unlock()
    }

    private func startPlayback(
        url: URL,
        headers: [String: String],
        container: ContainerFormat,
        startTimeSeconds: Double,
        selectedAudioTrackID: String?,
        selectedSubtitleTrackID: String?
    ) {
        let shouldStartCoordinator = seekCommitPolicy.enqueueRestart(targetSeconds: startTimeSeconds)
        let generation = seekCommitPolicy.generation
        playbackGeneration = generation
        currentURL = url
        currentHeaders = headers
        currentContainer = container
        currentStartTimeSeconds = max(0, startTimeSeconds)
        pendingRestartConfiguration = NativeMatroskaRestartConfiguration(
            generation: generation,
            url: url,
            headers: headers,
            container: container,
            targetSeconds: max(0, startTimeSeconds),
            selectedAudioTrackID: selectedAudioTrackID,
            selectedSubtitleTrackID: selectedSubtitleTrackID,
            isPaused: pendingPause
        )
        if let retiringGeneration = beginReaderRetirement() {
            invalidateCallbackOwnership(for: retiringGeneration)
        }
        let sharedRetirementTask = startOrReuseRetirement()
        guard shouldStartCoordinator else { return }
        restartCoordinatorID += 1
        let coordinatorID = restartCoordinatorID
        restartCoordinatorStartCount += 1
        restartTask = Task { [weak self, sharedRetirementTask] in
            await sharedRetirementTask?.value
            await self?.commitPendingRestart(coordinatorID: coordinatorID)
        }
    }

    private func commitPendingRestart(coordinatorID: Int) async {
        guard coordinatorID == restartCoordinatorID, !Task.isCancelled, !isTornDown else { return }
        guard let commit = seekCommitPolicy.takePendingRestart(),
              let configuration = pendingRestartConfiguration,
              commit.generation == configuration.generation,
              seekCommitPolicy.ownsCallbacks(from: commit.generation) else {
            seekCommitPolicy.finishRestart()
            restartTask = nil
            return
        }
        pendingRestartConfiguration = nil
        beginPlayback(configuration, readerGeneration: beginReaderStart())
        seekCommitPolicy.finishRestart()
        restartTask = nil
    }

    private func beginPlayback(
        _ configuration: NativeMatroskaRestartConfiguration,
        readerGeneration generation: Int
    ) {
        guard ownsCallbacks(from: generation) else { return }
        currentStartTimeSeconds = configuration.targetSeconds
        playbackStateLock.lock()
        playbackCanRun = false
        rebufferingForAudio = false
        consecutiveAudioStarvationTicks = 0
        reportedAudioStarvation = false
        pendingForwardSeekRequest = nil
        lastBufferWaitLogTime = 0
        audioRendererFailureReported = false
        audioStartupDegraded = false
        audioStartupWatchdog.reset()
        audioStarvationGate.reset()
        playbackStateLock.unlock()
        audioTimingNormalizer.reset()
        pauseStateGate.reset()
        videoSamples.removeAll()
        audioSamples.removeAll()
        videoHDRMetadata = nil
        resetPreferredDisplayCriteria()
        metricsLock.lock()
        metrics = NativeMatroskaSampleBufferMetrics()
        metricsLock.unlock()
        updateMetrics { $0.state = "openingByteSource" }
        diagnosticTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.publishDiagnostics(generation: generation)
        }
        playbackTask = Task { [weak self] in
            await self?.openDemuxAndPump(
                url: configuration.url,
                headers: configuration.headers,
                container: configuration.container,
                startTimeSeconds: configuration.targetSeconds,
                selectedAudioTrackID: configuration.selectedAudioTrackID,
                selectedSubtitleTrackID: configuration.selectedSubtitleTrackID,
                generation: generation
            )
        }
    }

    private func startOrReuseRetirement() -> Task<Void, Never>? {
        if let retirementTask { return retirementTask }
        let retiringGeneration = beginReaderRetirement()
        if let retiringGeneration {
            invalidateCallbackOwnership(for: retiringGeneration)
        }
        let previousTask = playbackTask
        guard retiringGeneration != nil || previousTask != nil || activeByteSource != nil else { return nil }
        playbackTask = nil
        diagnosticTimer?.invalidate()
        diagnosticTimer = nil
        stopDrainTimers()
        displayLayer.stopRequestingMediaData()
        audioRenderer.stopRequestingMediaData()
        retirementCoordinatorID += 1
        let coordinatorID = retirementCoordinatorID
        let task = Task { [self] in
            await performRetirement(generation: retiringGeneration, playbackTask: previousTask)
            if retirementCoordinatorID == coordinatorID {
                retirementTask = nil
            }
        }
        retirementTask = task
        return task
    }

    private func performRetirement(
        generation retiringGeneration: Int?,
        playbackTask previousTask: Task<Void, Never>?
    ) async {
        await beforePlaybackTaskCancellation?()
        previousTask?.cancel()
        if let retiringGeneration,
           let activeByteSource,
           activeByteSource.generation == retiringGeneration {
            await cancelActiveByteSourceIfNeeded(activeByteSource)
        }
        await previousTask?.value
        if let retiringGeneration {
            recordSourceCancellationIfNeeded(for: retiringGeneration)
            recordTeardownEvent(.readerFinished)
            finishReaderRetirement(retiringGeneration)
        }
        quiesceRenderQueuesAndFlush()
    }

    private func quiesceRenderQueuesAndFlush() {
        precondition(Thread.isMainThread, "Matroska renderer teardown must stay on the main thread")
        if let queue = DispatchQueue.getSpecific(key: renderQueueKey) {
            assertionFailure("Matroska renderer teardown re-entered the \(queue) render queue")
            AppLog.playback.error("nativeplayer.teardown.queue_reentry — queue=\(queue, privacy: .public)")
            return
        }
        videoQueue.sync {}
        recordTeardownEvent(.videoQueueQuiesced)
        audioQueue.sync {}
        recordTeardownEvent(.audioQueueQuiesced)
        displayLayer.flushAndRemoveImage()
        audioRenderer.flush()
        recordTeardownEvent(.renderersFlushed)
        videoSamples.removeAll()
        audioSamples.removeAll()
        videoHDRMetadata = nil
        resetPreferredDisplayCriteria()
        playbackStateLock.lock()
        playbackCanRun = false
        rebufferingForAudio = false
        consecutiveAudioStarvationTicks = 0
        reportedAudioStarvation = false
        pendingForwardSeekRequest = nil
        lastBufferWaitLogTime = 0
        audioRendererFailureReported = false
        audioStartupDegraded = false
        audioStartupWatchdog.reset()
        audioStarvationGate.reset()
        playbackStateLock.unlock()
        pauseStateGate.reset()
    }

    private func stopPlayback(publishFinalPlaybackTime: Bool = true) {
        let finalPlaybackTime = synchronizer.currentTime().matroskaSafeSeconds
        if publishFinalPlaybackTime, !isTornDown, let onPlaybackTime {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isTornDown else { return }
                self.recordCallbackDelivery()
                onPlaybackTime(finalPlaybackTime)
            }
        }
        seekCommitPolicy.cancelAll()
        playbackGeneration = seekCommitPolicy.generation
        pendingRestartConfiguration = nil
        restartCoordinatorID += 1
        restartTask?.cancel()
        restartTask = nil
        let retiringGeneration = beginReaderRetirement()
        if let retiringGeneration {
            invalidateCallbackOwnership(for: retiringGeneration)
        }
        _ = startOrReuseRetirement()
    }

    private func openDemuxAndPump(
        url: URL,
        headers: [String: String],
        container: ContainerFormat,
        startTimeSeconds: Double,
        selectedAudioTrackID: String?,
        selectedSubtitleTrackID: String?,
        generation: Int
    ) async {
        guard ownsCallbacks(from: generation) else { return }
        AppLog.playback.notice("nativeplayer.sampleReader.start — backend=\(Self.demuxerName(for: container), privacy: .public)")
        let source = byteSourceFactory(url, headers)
        setActiveByteSource(source, generation: generation)
        let completedWithOwnedCallbacks = await runDemuxAndPump(
            source: source,
            container: container,
            startTimeSeconds: startTimeSeconds,
            selectedAudioTrackID: selectedAudioTrackID,
            selectedSubtitleTrackID: selectedSubtitleTrackID,
            generation: generation
        )
        if let activeByteSource, activeByteSource.generation == generation {
            await cancelActiveByteSourceIfNeeded(activeByteSource)
        }
        clearActiveByteSource(source, generation: generation)
        if completedWithOwnedCallbacks {
            finishReaderAfterCompletion(generation)
        }
    }

    private func runDemuxAndPump(
        source: any MediaByteSource,
        container: ContainerFormat,
        startTimeSeconds: Double,
        selectedAudioTrackID: String?,
        selectedSubtitleTrackID: String?,
        generation: Int
    ) async -> Bool {
        var completedWithOwnedCallbacks = false
        do {
            let demuxer = Self.makeDemuxer(source: source, container: container)
            let stream = try await demuxer.open()
            try Task.checkCancellation()
            guard ownsCallbacks(from: generation) else { return false }
            if startTimeSeconds > 0 {
                try await demuxer.seek(to: CMTime(seconds: startTimeSeconds, preferredTimescale: 1000))
                try Task.checkCancellation()
                guard ownsCallbacks(from: generation) else { return false }
            }
            guard let videoTrack = stream.tracks.first(where: { $0.kind == .video }) else {
                throw NativeMatroskaSampleBufferPlayerError.noVideoTrack
            }
            videoHDRMetadata = videoTrack.hdrMetadata
            let audioTrack = Self.selectedTrack(
                kind: .audio,
                in: stream,
                selectedID: selectedAudioTrackID
            )
            let subtitleTrack = Self.selectedSubtitleTrack(
                in: stream,
                selectedID: selectedSubtitleTrackID
            )
            let videoDecoder = try VideoDecoderFactory().makeDecoder(for: videoTrack)
            try await videoDecoder.configure(track: videoTrack)
            try Task.checkCancellation()
            guard ownsCallbacks(from: generation) else { return false }
            let audioDecoder = await makeAudioDecoder(audioTrack, generation: generation)
            try Task.checkCancellation()
            guard ownsCallbacks(from: generation) else { return false }
            markReaderActive(generation)
            resetPlaybackReadiness(hasAudio: audioDecoder != nil)

            updateMetrics {
                $0.state = pendingPause ? "paused" : "buffering"
                $0.videoDecoderBackend = "VideoToolbox"
                $0.audioDecoderBackend = audioDecoder == nil ? "none" : "AppleAudioToolbox"
                $0.startTime = startTimeSeconds
                $0.hdrFormat = videoTrack.hdrMetadata?.format.rawValue ?? "unknown"
                $0.dolbyVisionProfile = videoTrack.hdrMetadata?.dolbyVision?.profile.map(String.init) ?? "none"
            }
            AppLog.playback.notice("nativeplayer.videoRenderer.start — backend=AVSampleBufferDisplayLayer")
            AppLog.playback.notice("nativeplayer.audioRenderer.start — backend=AVSampleBufferAudioRenderer")
            startClock(at: startTimeSeconds, paused: true)
            startDrainTimers(generation: generation)
            try await pumpPackets(
                demuxer: demuxer,
                videoTrack: videoTrack,
                audioTrack: audioTrack,
                subtitleTrack: subtitleTrack,
                videoDecoder: videoDecoder,
                audioDecoder: audioDecoder,
                startTimeSeconds: startTimeSeconds,
                generation: generation
            )
            completedWithOwnedCallbacks = ownsCallbacks(from: generation)
        } catch {
            if !Task.isCancelled, ownsCallbacks(from: generation) {
                updateMetrics {
                    $0.state = "failed"
                    $0.failure = error.localizedDescription
                }
                publishDiagnostics(generation: generation)
                completedWithOwnedCallbacks = true
            }
        }
        return completedWithOwnedCallbacks
    }

    private func setActiveByteSource(_ source: any MediaByteSource, generation: Int) {
        precondition(activeByteSource == nil, "A Matroska byte source was replaced before retirement finished")
        activeByteSource = NativeMatroskaActiveByteSource(generation: generation, source: source)
        activeReaderCount += 1
        maximumConcurrentReaderCount = max(maximumConcurrentReaderCount, activeReaderCount)
    }

    private func clearActiveByteSource(_ source: any MediaByteSource, generation: Int) {
        _ = source
        guard activeByteSource?.generation == generation else { return }
        activeByteSource = nil
        activeReaderCount = max(0, activeReaderCount - 1)
    }

    private func cancelActiveByteSourceIfNeeded(_ activeSource: NativeMatroskaActiveByteSource) async {
        let cancellationTask: Task<Void, Never>
        if let existingTask = activeSource.cancellationTask {
            cancellationTask = existingTask
        } else {
            let source = activeSource.source
            let task = Task { await source.cancel() }
            activeSource.cancellationTask = task
            cancellationTask = task
        }
        await cancellationTask.value
        guard !activeSource.cancellationCompleted else { return }
        activeSource.cancellationCompleted = true
        cancelledSourceGenerations.insert(activeSource.generation)
        recordSourceCancellationIfNeeded(for: activeSource.generation)
    }

    private func recordSourceCancellationIfNeeded(for generation: Int) {
        guard cancelledSourceGenerations.contains(generation),
              invalidatedCallbackGenerations.contains(generation),
              recordedSourceCancellationGenerations.insert(generation).inserted else { return }
        recordTeardownEvent(.sourceCancelled)
    }

    private func recordTeardownEvent(_ event: NativeMatroskaTeardownEvent) {
        teardownEvents.append(event)
        teardownEventObserver?(event)
    }

    private func makeAudioDecoder(
        _ track: NativeMediaCore.MediaTrack?,
        generation: Int
    ) async -> (any AudioDecoder)? {
        guard let track else { return nil }
        do {
            let decoder = try AudioDecoderFactory().makeDecoder(for: track)
            try await decoder.configure(track: track)
            guard !Task.isCancelled, ownsCallbacks(from: generation) else { return nil }
            return decoder
        } catch {
            guard !Task.isCancelled, ownsCallbacks(from: generation) else { return nil }
            updateMetrics {
                $0.audioDecoderBackend = "missing"
                $0.unsupportedModules.append("audio \(track.codec): \(error.localizedDescription)")
            }
            return nil
        }
    }

    private func pumpPackets(
        demuxer: any MediaDemuxer,
        videoTrack: NativeMediaCore.MediaTrack,
        audioTrack: NativeMediaCore.MediaTrack?,
        subtitleTrack: NativeMediaCore.MediaTrack?,
        videoDecoder: any VideoDecoder,
        audioDecoder: (any AudioDecoder)?,
        startTimeSeconds: Double,
        generation: Int
    ) async throws {
        var forwardSeekState: NativeMatroskaForwardSeekState? = startTimeSeconds > 0
            ? NativeMatroskaForwardSeekState(targetSeconds: startTimeSeconds)
            : nil
        while !Task.isCancelled, ownsCallbacks(from: generation) {
            if let request = takePendingForwardSeekRequest() {
                try await demuxer.seek(to: CMTime(seconds: request.targetSeconds, preferredTimescale: 1000))
                try Task.checkCancellation()
                guard ownsCallbacks(from: generation) else { return }
                forwardSeekState = NativeMatroskaForwardSeekState(targetSeconds: request.targetSeconds)
                AppLog.playback.notice("nativeplayer.seek.demuxer_applied — target=\(request.targetSeconds, privacy: .public)")
                continue
            }
            guard let packet = try await demuxer.readNextPacket() else { break }
            try Task.checkCancellation()
            guard ownsCallbacks(from: generation) else { return }
            if var state = forwardSeekState {
                let shouldSkip = state.shouldSkip(
                    packet,
                    videoTrackID: videoTrack.trackId,
                    audioTrackID: audioTrack?.trackId,
                    subtitleTrackID: subtitleTrack?.trackId
                )
                forwardSeekState = state
                if shouldSkip { continue }
            }
            if packet.trackID == videoTrack.trackId {
                guard let frame = try await videoDecoder.decode(packet: packet), let sample = frame.sampleBuffer else { continue }
                try Task.checkCancellation()
                guard ownsCallbacks(from: generation) else { return }
                try await queueVideo(sample, generation: generation)
            } else if packet.trackID == audioTrack?.trackId, let audioDecoder {
                guard let frame = try await audioDecoder.decode(packet: packet), let sample = frame.sampleBuffer else { continue }
                try Task.checkCancellation()
                guard ownsCallbacks(from: generation) else { return }
                try await queueAudio(sample, generation: generation)
            } else if packet.trackID == subtitleTrack?.trackId {
                recordSubtitlePacket(packet, generation: generation)
            }
        }
        guard ownsCallbacks(from: generation) else { return }
        updateMetrics { if $0.state != "failed" { $0.state = "ended" } }
        publishDiagnostics(generation: generation)
    }

    private func takePendingForwardSeekRequest() -> NativePlayerSeekRequest? {
        playbackStateLock.lock()
        defer { playbackStateLock.unlock() }
        let request = pendingForwardSeekRequest
        pendingForwardSeekRequest = nil
        return request
    }

    private func queueVideo(_ sample: CMSampleBuffer, generation: Int) async throws {
        guard ownsCallbacks(from: generation) else { return }
        markVideoPrerollIfNeeded(sample)
        try await waitForCapacity(in: videoSamples, generation: generation)
        guard ownsCallbacks(from: generation) else { return }
        guard videoSamples.push(sample) else { return }
        refreshQueueMetrics()
        requestVideoDrain(generation: generation)
        activatePlaybackIfReady(generation: generation)
    }

    private func queueAudio(_ sample: CMSampleBuffer, generation: Int) async throws {
        guard ownsCallbacks(from: generation) else { return }
        guard !dropAudioPrerollIfNeeded(sample) else { return }
        let normalization = try audioTimingNormalizer.normalized(sample)
        if normalization.rewrotePresentationTimestamp {
            updateMetrics {
                $0.audioPTSRewrites += 1
                $0.maxAudioPTSCorrectionSeconds = max(
                    $0.maxAudioPTSCorrectionSeconds,
                    normalization.ptsCorrectionSeconds
                )
            }
        }
        try await waitForCapacity(in: audioSamples, generation: generation)
        guard ownsCallbacks(from: generation) else { return }
        guard audioSamples.push(normalization.sampleBuffer) else { return }
        refreshQueueMetrics()
        requestAudioDrain(generation: generation)
        activatePlaybackIfReady(generation: generation)
    }

    private func waitForCapacity(in queue: NativeSampleBufferQueue, generation: Int) async throws {
        while queue.isFull {
            try Task.checkCancellation()
            guard ownsCallbacks(from: generation) else { throw CancellationError() }
            requestVideoDrain(generation: generation)
            requestAudioDrain(generation: generation)
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func setPaused(_ paused: Bool) {
        playbackStateLock.lock()
        pendingPause = paused
        let canRun = playbackCanRun
        playbackStateLock.unlock()
        guard pauseStateGate.shouldApply(paused) else { return }
        pauseStateApplicationCount += 1
        guard paused || canRun else {
            updateMetrics { $0.state = "buffering" }
            return
        }
        let time = synchronizer.currentTime()
        synchronizer.setRate(paused ? 0 : 1, time: time)
        updateMetrics { $0.state = paused ? "paused" : "playing" }
    }

    private func startClock(at seconds: Double, paused: Bool) {
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 1000)
        synchronizer.setRate(paused ? 0 : 1, time: time)
        pauseStateGate.markApplied(paused)
        updateMetrics { $0.state = pendingPause ? "paused" : "buffering" }
    }

    private func startDrainTimers(generation: Int) {
        stopDrainTimers()
        videoDrainTimer = makeDrainTimer(queue: videoQueue, interval: 1.0 / 60.0) { [weak self] in
            self?.drainVideoQueueNow(generation: generation)
        }
        audioRenderer.requestMediaDataWhenReady(on: audioQueue) { [weak self] in
            self?.drainAudioQueueNow(generation: generation)
        }
    }

    private func stopDrainTimers() {
        videoDrainTimer?.cancel()
        audioRenderer.stopRequestingMediaData()
        videoDrainTimer = nil
    }

    private func makeDrainTimer(
        queue: DispatchQueue,
        interval: TimeInterval,
        handler: @escaping () -> Void
    ) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(3))
        timer.setEventHandler(handler: handler)
        timer.resume()
        return timer
    }

    private func requestVideoDrain(generation: Int) {
        videoQueue.async { [weak self] in
            self?.drainVideoQueueNow(generation: generation)
        }
    }

    private func requestAudioDrain(generation: Int) {
        audioQueue.async { [weak self] in
            self?.drainAudioQueueNow(generation: generation)
        }
    }

    private func drainVideoQueueNow(generation: Int) {
        guard ownsCallbacks(from: generation) else { return }
        while ownsCallbacks(from: generation), displayLayer.isReadyForMoreMediaData {
            guard let sample = videoSamples.pop() else { break }
            guard ownsCallbacks(from: generation) else { return }
            applyPreferredDisplayCriteriaIfNeeded(from: sample)
            displayLayer.enqueue(sample)
            recordVideoSample(sample, generation: generation)
        }
        guard ownsCallbacks(from: generation) else { return }
        refreshQueueMetrics()
    }

    private func drainAudioQueueNow(generation: Int) {
        guard ownsCallbacks(from: generation) else { return }
        guard !handleAudioRendererFailureIfNeeded(generation: generation) else { return }
        var hadAudio = false
        while ownsCallbacks(from: generation), audioRenderer.isReadyForMoreMediaData {
            guard let sample = audioSamples.pop() else { break }
            guard ownsCallbacks(from: generation) else { return }
            hadAudio = true
            audioRenderer.enqueue(sample)
            recordAudioSample(sample, generation: generation)
            if handleAudioRendererFailureIfNeeded(generation: generation) { return }
        }
        guard ownsCallbacks(from: generation) else { return }
        refreshQueueMetrics()
        if !hadAudio, audioRenderer.isReadyForMoreMediaData, isRunningPlayback(), isAudioStarved() {
            recordAudioStarvationIfNeeded()
        } else {
            resetAudioStarvation()
            activatePlaybackIfReady(generation: generation)
        }
    }

    private func isRunningPlayback() -> Bool {
        playbackStateLock.lock()
        defer { playbackStateLock.unlock() }
        return playbackCanRun && !pendingPause
    }

    private func resetPlaybackReadiness(hasAudio: Bool) {
        playbackStateLock.lock()
        hasAudioTrackForBuffering = hasAudio
        playbackCanRun = false
        rebufferingForAudio = false
        consecutiveAudioStarvationTicks = 0
        reportedAudioStarvation = false
        audioStarvationGate.reset()
        playbackStateLock.unlock()
        updateMetrics {
            $0.videoPrimedPacketCount = 0
            $0.audioPrimedPacketCount = 0
            $0.audioStarvationTicks = 0
            $0.audioStarvationSeconds = 0
        }
    }

    private func recordAudioStarvationIfNeeded() {
        playbackStateLock.lock()
        let decision = audioStarvationGate.update(
            isStarved: true,
            now: ProcessInfo.processInfo.systemUptime
        )
        consecutiveAudioStarvationTicks = decision.ticks
        let shouldReport = decision.shouldRebuffer && !reportedAudioStarvation
        if shouldReport {
            reportedAudioStarvation = true
        }
        playbackStateLock.unlock()
        updateMetrics {
            $0.audioStarvationTicks = decision.ticks
            $0.audioStarvationSeconds = decision.elapsedSeconds
        }
        if shouldReport {
            updateMetrics {
                $0.audioUnderruns += 1
            }
            AppLog.playback.warning("nativeplayer.audio.starvation — elapsed=\(decision.elapsedSeconds, privacy: .public) ticks=\(decision.ticks, privacy: .public)")
        }
    }

    private func resetAudioStarvation() {
        playbackStateLock.lock()
        let shouldReset = consecutiveAudioStarvationTicks != 0 || audioStarvationGate.starvationStartTime != nil
        consecutiveAudioStarvationTicks = 0
        reportedAudioStarvation = false
        audioStarvationGate.reset()
        playbackStateLock.unlock()
        if shouldReset {
            updateMetrics {
                $0.audioStarvationTicks = 0
                $0.audioStarvationSeconds = 0
            }
        }
    }

    private func isAudioStarved() -> Bool {
        metricsLock.lock()
        let snapshot = metrics
        metricsLock.unlock()
        return bufferPolicy.shouldRebufferAudio(
            snapshot: bufferSnapshot(from: snapshot),
            needsAudio: true,
            isPlaying: true
        )
    }

    private func activatePlaybackIfReady(generation: Int) {
        guard ownsCallbacks(from: generation) else { return }
        metricsLock.lock()
        let snapshot = metrics
        metricsLock.unlock()

        playbackStateLock.lock()
        let needsAudio = hasAudioTrackForBuffering
        let paused = pendingPause
        let isRebuffering = rebufferingForAudio
        if playbackCanRun {
            playbackStateLock.unlock()
            return
        }
        let bufferSnapshot = bufferSnapshot(from: snapshot)
        var decision = bufferPolicy.decision(
            snapshot: bufferSnapshot,
            needsAudio: needsAudio,
            isRebuffering: isRebuffering
        )
        if shouldDegradeAudioStartup(
            snapshot: snapshot,
            bufferSnapshot: bufferSnapshot,
            decision: decision,
            needsAudio: needsAudio
        ) {
            hasAudioTrackForBuffering = false
            audioStartupDegraded = true
            audioRendererFailureReported = true
            audioStartupWatchdog.reset()
            audioRenderer.stopRequestingMediaData()
            audioRenderer.flush()
            audioSamples.removeAll()
            refreshQueueMetrics()
            decision = bufferPolicy.decision(
                snapshot: bufferSnapshot,
                needsAudio: false,
                isRebuffering: isRebuffering
            )
            updateMetrics {
                $0.audioDecoderBackend = "degraded"
                if !$0.unsupportedModules.contains(where: { $0.hasPrefix("audioStartupDegraded") }) {
                    $0.unsupportedModules.append("audioStartupDegraded: video started after audio renderer did not prime")
                }
            }
            AppLog.playback.error("nativeplayer.audio.startup_degraded — videoPackets=\(snapshot.videoPacketCount) audioPackets=\(snapshot.audioPacketCount) audioPrimed=\(snapshot.audioPrimedPacketCount) audioAhead=\(decision.audioAheadSeconds, privacy: .public)")
        }
        updateMetrics {
            $0.videoAheadSeconds = decision.videoAheadSeconds
            $0.audioAheadSeconds = decision.audioAheadSeconds
        }
        guard decision.canStart else {
            logBufferWaitIfNeeded(snapshot: snapshot, decision: decision, needsAudio: needsAudio)
            playbackStateLock.unlock()
            return
        }
        playbackCanRun = true
        rebufferingForAudio = false
        consecutiveAudioStarvationTicks = 0
        audioStarvationGate.reset()
        playbackStateLock.unlock()

        guard ownsCallbacks(from: generation) else { return }
        let clockSeconds = synchronizer.currentTime().matroskaSafeSeconds
        let time = CMTime(seconds: max(0, clockSeconds, snapshot.startTime), preferredTimescale: 1000)
        synchronizer.setRate(paused ? 0 : 1, time: time)
        pauseStateGate.markApplied(paused)
        updateMetrics {
            $0.state = paused ? "paused" : "playing"
            $0.audioStarvationTicks = 0
            $0.audioStarvationSeconds = 0
        }
        AppLog.playback.notice("nativeplayer.buffering.ready — videoPackets=\(snapshot.videoPacketCount) audioPackets=\(snapshot.audioPacketCount) audioPrimed=\(snapshot.audioPrimedPacketCount) requiredAudioPrimed=\(decision.requiredAudioPrimedPacketCount) audioAhead=\(decision.audioAheadSeconds, privacy: .public) videoAhead=\(decision.videoAheadSeconds, privacy: .public)")
    }

    private func shouldDegradeAudioStartup(
        snapshot: NativeMatroskaSampleBufferMetrics,
        bufferSnapshot: NativePlaybackBufferSnapshot,
        decision: NativePlaybackBufferDecision,
        needsAudio: Bool
    ) -> Bool {
        guard !audioStartupDegraded else { return false }
        return audioStartupWatchdog.shouldDegradeAudio(
            now: ProcessInfo.processInfo.systemUptime,
            snapshot: bufferSnapshot,
            decision: decision,
            needsAudio: needsAudio,
            maximumWaitSeconds: bufferPolicy.maximumAudioStartupWaitSeconds
        ) || shouldImmediatelyDegradeFailedAudioRenderer(snapshot: snapshot, needsAudio: needsAudio)
    }

    private func shouldImmediatelyDegradeFailedAudioRenderer(
        snapshot: NativeMatroskaSampleBufferMetrics,
        needsAudio: Bool
    ) -> Bool {
        guard needsAudio, audioRenderer.status == .failed else { return false }
        return snapshot.videoPacketCount > 0
    }

    private func handleAudioRendererFailureIfNeeded(generation: Int) -> Bool {
        guard ownsCallbacks(from: generation) else { return true }
        guard audioRenderer.status == .failed else { return false }
        playbackStateLock.lock()
        let alreadyReported = audioRendererFailureReported
        audioRendererFailureReported = true
        hasAudioTrackForBuffering = false
        playbackStateLock.unlock()
        if !alreadyReported {
            let message = audioRenderer.error?.localizedDescription ?? "AVSampleBufferAudioRenderer failed while accepting compressed audio."
            updateMetrics {
                $0.audioDecoderBackend = "failed"
                $0.unsupportedModules.append("audioRendererFailed: \(message)")
            }
            AppLog.playback.error("nativeplayer.audioRenderer.failed — \(message, privacy: .public)")
        }
        audioSamples.removeAll()
        refreshQueueMetrics()
        activatePlaybackIfReady(generation: generation)
        return true
    }

    private func logBufferWaitIfNeeded(
        snapshot: NativeMatroskaSampleBufferMetrics,
        decision: NativePlaybackBufferDecision,
        needsAudio: Bool
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastBufferWaitLogTime >= 3.0 else { return }
        lastBufferWaitLogTime = now
        AppLog.playback.notice("nativeplayer.buffering.wait — videoPackets=\(snapshot.videoPacketCount) audioPackets=\(snapshot.audioPacketCount) audioPrimed=\(snapshot.audioPrimedPacketCount) requiredAudioPrimed=\(decision.requiredAudioPrimedPacketCount) needsAudio=\(needsAudio, privacy: .public) audioAhead=\(decision.audioAheadSeconds, privacy: .public) requiredAudioAhead=\(decision.requiredAudioAheadSeconds, privacy: .public) videoAhead=\(decision.videoAheadSeconds, privacy: .public) requiredVideoAhead=\(decision.requiredVideoAheadSeconds, privacy: .public)")
    }

    private func markVideoPrerollIfNeeded(_ sample: CMSampleBuffer) {
        guard isBeforeRequestedStart(sample) else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) else { return }
        for index in 0..<CFArrayGetCount(attachments) {
            let rawAttachment = CFArrayGetValueAtIndex(attachments, index)
            let attachment = unsafeBitCast(rawAttachment, to: CFMutableDictionary.self)
            CFDictionarySetValue(
                attachment,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DoNotDisplay).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        updateMetrics { $0.videoPrerollHidden += 1 }
    }

    private func dropAudioPrerollIfNeeded(_ sample: CMSampleBuffer) -> Bool {
        guard isBeforeRequestedStart(sample) else { return false }
        updateMetrics { $0.audioPrerollDropped += 1 }
        return true
    }

    private func isBeforeRequestedStart(_ sample: CMSampleBuffer) -> Bool {
        guard currentStartTimeSeconds > 0 else { return false }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample).matroskaSafeSeconds
        return pts < currentStartTimeSeconds - 0.020
    }

    private func refreshQueueMetrics() {
        let video = videoSamples.snapshot()
        let audio = audioSamples.snapshot()
        updateMetrics {
            $0.videoQueueDepth = video.count
            $0.audioQueueDepth = audio.count
            $0.videoQueuedSeconds = video.durationSeconds
            $0.audioQueuedSeconds = audio.durationSeconds
        }
    }

    private func bufferSnapshot(from metrics: NativeMatroskaSampleBufferMetrics) -> NativePlaybackBufferSnapshot {
        NativePlaybackBufferSnapshot(
            startTime: metrics.startTime,
            currentVideoPTS: metrics.currentPTS,
            currentAudioPTS: metrics.audioPTS,
            playbackTime: synchronizer.currentTime().matroskaSafeSeconds,
            videoQueuedSeconds: metrics.videoQueuedSeconds,
            audioQueuedSeconds: metrics.audioQueuedSeconds,
            videoPacketCount: metrics.videoPacketCount,
            audioPacketCount: metrics.audioPacketCount,
            videoPrimedPacketCount: metrics.videoPrimedPacketCount,
            audioPrimedPacketCount: metrics.audioPrimedPacketCount
        )
    }

    private func recordVideoSample(_ sample: CMSampleBuffer, generation: Int) {
        guard ownsCallbacks(from: generation) else { return }
        let metadata = HDRCoreMediaMapper.metadata(from: CMSampleBufferGetFormatDescription(sample))
        updateMetrics {
            $0.videoPacketCount += 1
            $0.videoPrimedPacketCount += 1
            $0.currentPTS = CMSampleBufferGetPresentationTimeStamp(sample).matroskaSafeSeconds
            $0.droppedFrames = displayLayer.status == .failed ? $0.droppedFrames + 1 : $0.droppedFrames
            if let metadata {
                $0.hdrFormat = metadata.format.rawValue
                $0.dolbyVisionProfile = metadata.dolbyVision?.profile.map(String.init) ?? "none"
            }
        }
        activatePlaybackIfReady(generation: generation)
    }

    private func applyHDRMetrics(from metadata: HDRMetadata?) {
        metrics.hdrFormat = metadata?.format.rawValue ?? "unknown"
        metrics.dolbyVisionProfile = metadata?.dolbyVision?.profile.map(String.init) ?? "none"
    }

    private func applyPreferredDisplayCriteriaIfNeeded(from sample: CMSampleBuffer) {
#if os(tvOS)
        displayCriteriaCoordinator.scheduleApply(from: sample)
#endif
    }

    private func resetPreferredDisplayCriteria() {
#if os(tvOS)
        displayCriteriaCoordinator.reset()
#endif
    }

    private func recordAudioSample(_ sample: CMSampleBuffer, generation: Int) {
        guard ownsCallbacks(from: generation) else { return }
        let sampleCount = CMSampleBufferGetNumSamples(sample)
        updateMetrics {
            $0.audioPacketCount += 1
            $0.audioRenderedSampleCount += sampleCount
            $0.maxAudioSamplesPerBuffer = max($0.maxAudioSamplesPerBuffer, sampleCount)
            $0.audioPrimedPacketCount += 1
            $0.audioPTS = CMSampleBufferGetPresentationTimeStamp(sample).matroskaSafeSeconds
        }
        activatePlaybackIfReady(generation: generation)
    }

    private func recordSubtitlePacket(_ packet: MediaPacket, generation: Int) {
        guard ownsCallbacks(from: generation) else { return }
        guard let text = String(data: packet.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        let duration = packet.timestamp.duration ?? CMTime(seconds: 3, preferredTimescale: 1000)
        let cue = SubtitleCue(
            id: "\(packet.trackID)-\(subtitleCues.count)",
            start: packet.timestamp.pts,
            end: packet.timestamp.pts + duration,
            text: text
        )
        DispatchQueue.main.async { [weak self] in
            guard let self, self.ownsCallbacks(from: generation) else { return }
            self.subtitleCues.append(cue)
            self.renderActiveSubtitles()
        }
    }

    private func updateMetrics(_ update: (inout NativeMatroskaSampleBufferMetrics) -> Void) {
        metricsLock.lock()
        update(&metrics)
        metricsLock.unlock()
    }

    private func publishDiagnostics(generation: Int) {
        guard ownsCallbacks(from: generation) else { return }
        metricsLock.lock()
        var snapshot = metrics
        metricsLock.unlock()
        snapshot.playbackTime = synchronizer.currentTime().matroskaSafeSeconds
        let bufferDecision = bufferPolicy.decision(
            snapshot: bufferSnapshot(from: snapshot),
            needsAudio: snapshot.requiresAudioForBuffering,
            isRebuffering: snapshot.state == "buffering"
        )
        snapshot.videoAheadSeconds = bufferDecision.videoAheadSeconds
        snapshot.audioAheadSeconds = bufferDecision.audioAheadSeconds
        renderActiveSubtitles()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.ownsCallbacks(from: generation) else { return }
            self.recordCallbackDelivery()
            self.onPlaybackTime?(snapshot.playbackTime)
            self.onDiagnostics?(
                snapshot.overlayLines(base: self.baseDiagnostics)
                    + ["readerGeneration=\(generation)"]
            )
        }
    }

    private func recordCallbackDelivery() {
        if isTornDown {
            callbackCountAfterDismantle += 1
        }
    }

    private func renderActiveSubtitles() {
        let active = subtitleClock.activeCues(from: subtitleCues, at: synchronizer.currentTime())
        subtitleOverlay.render(cues: active)
        updateMetrics { $0.activeSubtitleText = active.first?.text }
    }

    private static func canRenderSubtitle(_ track: NativeMediaCore.MediaTrack) -> Bool {
        switch MatroskaCodecMapper.subtitleFormat(track.codecID ?? track.codec) {
        case .srt, .webVTT, .ass, .ssa, .matroskaText:
            return true
        default:
            return false
        }
    }

    private static func selectedTrack(
        kind: MediaTrackKind,
        in stream: DemuxerStreamInfo,
        selectedID: String?
    ) -> NativeMediaCore.MediaTrack? {
        let tracks = stream.tracks.filter { $0.kind == kind }
        guard let selectedID else { return tracks.first }
        return tracks.first { "\($0.trackId)" == selectedID } ?? tracks.first
    }

    private static func selectedSubtitleTrack(
        in stream: DemuxerStreamInfo,
        selectedID: String?
    ) -> NativeMediaCore.MediaTrack? {
        guard let selectedID else { return nil }
        return stream.tracks.first {
            $0.kind == .subtitle
                && "\($0.trackId)" == selectedID
                && canRenderSubtitle($0)
        }
    }

    private static func makeDemuxer(source: any MediaByteSource, container: ContainerFormat) -> any MediaDemuxer {
        switch container {
        case .mpegTS, .m2ts:
            return MPEGTransportStreamDemuxer(source: source, format: container)
        case .webm:
            return MatroskaDemuxer(source: source, profile: .webm)
        default:
            return MatroskaDemuxer(source: source)
        }
    }

    private static func demuxerName(for container: ContainerFormat) -> String {
        switch container {
        case .mpegTS, .m2ts:
            return "MPEGTransportStreamDemuxer"
        case .webm:
            return "WebMDemuxer"
        default:
            return "MatroskaDemuxer"
        }
    }
}
