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

final class NativeMatroskaSampleBufferPlayerController: UIViewController {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let audioRenderer = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let subtitleOverlay = NativeSubtitleOverlayView()
    private let videoQueue = DispatchQueue(label: "reelfin.nativeplayer.mkv.video", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "reelfin.nativeplayer.mkv.audio", qos: .userInitiated)
    private let metricsLock = NSLock()
    private let playbackStateLock = NSLock()
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
        stopPlayback(publishFinalPlaybackTime: false)
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
        publishDiagnostics()
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
        guard playbackTask != nil else { return false }
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
        startDrainTimers()
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
        stopPlayback(publishFinalPlaybackTime: false)
        playbackGeneration += 1
        currentURL = url
        currentHeaders = headers
        currentContainer = container
        currentStartTimeSeconds = startTimeSeconds
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
            self?.publishDiagnostics()
        }
        playbackTask = Task { [weak self] in
            await self?.openDemuxAndPump(
                url: url,
                headers: headers,
                container: container,
                startTimeSeconds: startTimeSeconds,
                selectedAudioTrackID: selectedAudioTrackID,
                selectedSubtitleTrackID: selectedSubtitleTrackID
            )
        }
    }

    private func stopPlayback(publishFinalPlaybackTime: Bool = true) {
        let finalPlaybackTime = synchronizer.currentTime().matroskaSafeSeconds
        if publishFinalPlaybackTime, !isTornDown, let onPlaybackTime {
            DispatchQueue.main.async {
                onPlaybackTime(finalPlaybackTime)
            }
        }
        playbackTask?.cancel()
        playbackTask = nil
        diagnosticTimer?.invalidate()
        diagnosticTimer = nil
        stopDrainTimers()
        displayLayer.stopRequestingMediaData()
        audioRenderer.stopRequestingMediaData()
        displayLayer.flushAndRemoveImage()
        audioRenderer.flush()
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

    private func openDemuxAndPump(
        url: URL,
        headers: [String: String],
        container: ContainerFormat,
        startTimeSeconds: Double,
        selectedAudioTrackID: String?,
        selectedSubtitleTrackID: String?
    ) async {
        do {
            AppLog.playback.notice("nativeplayer.sampleReader.start — backend=\(Self.demuxerName(for: container), privacy: .public)")
            let source = HTTPRangeByteSource(url: url, headers: headers)
            let demuxer = Self.makeDemuxer(source: source, container: container)
            let stream = try await demuxer.open()
            if startTimeSeconds > 0 {
                try await demuxer.seek(to: CMTime(seconds: startTimeSeconds, preferredTimescale: 1000))
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
            let audioDecoder = await makeAudioDecoder(audioTrack)
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
            startDrainTimers()
            try await pumpPackets(
                demuxer: demuxer,
                videoTrack: videoTrack,
                audioTrack: audioTrack,
                subtitleTrack: subtitleTrack,
                videoDecoder: videoDecoder,
                audioDecoder: audioDecoder,
                startTimeSeconds: startTimeSeconds
            )
        } catch {
            updateMetrics {
                $0.state = "failed"
                $0.failure = error.localizedDescription
            }
            publishDiagnostics()
        }
    }

    private func makeAudioDecoder(_ track: NativeMediaCore.MediaTrack?) async -> (any AudioDecoder)? {
        guard let track else { return nil }
        do {
            let decoder = try AudioDecoderFactory().makeDecoder(for: track)
            try await decoder.configure(track: track)
            return decoder
        } catch {
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
        startTimeSeconds: Double
    ) async throws {
        var forwardSeekState: NativeMatroskaForwardSeekState? = startTimeSeconds > 0
            ? NativeMatroskaForwardSeekState(targetSeconds: startTimeSeconds)
            : nil
        while !Task.isCancelled {
            if let request = takePendingForwardSeekRequest() {
                try await demuxer.seek(to: CMTime(seconds: request.targetSeconds, preferredTimescale: 1000))
                forwardSeekState = NativeMatroskaForwardSeekState(targetSeconds: request.targetSeconds)
                AppLog.playback.notice("nativeplayer.seek.demuxer_applied — target=\(request.targetSeconds, privacy: .public)")
                continue
            }
            guard let packet = try await demuxer.readNextPacket() else { break }
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
                try await queueVideo(sample)
            } else if packet.trackID == audioTrack?.trackId, let audioDecoder {
                guard let frame = try await audioDecoder.decode(packet: packet), let sample = frame.sampleBuffer else { continue }
                try await queueAudio(sample)
            } else if packet.trackID == subtitleTrack?.trackId {
                recordSubtitlePacket(packet)
            }
        }
        updateMetrics { if $0.state != "failed" { $0.state = "ended" } }
        publishDiagnostics()
    }

    private func takePendingForwardSeekRequest() -> NativePlayerSeekRequest? {
        playbackStateLock.lock()
        defer { playbackStateLock.unlock() }
        let request = pendingForwardSeekRequest
        pendingForwardSeekRequest = nil
        return request
    }

    private func queueVideo(_ sample: CMSampleBuffer) async throws {
        markVideoPrerollIfNeeded(sample)
        try await waitForCapacity(in: videoSamples)
        guard videoSamples.push(sample) else { return }
        refreshQueueMetrics()
        requestVideoDrain()
        activatePlaybackIfReady()
    }

    private func queueAudio(_ sample: CMSampleBuffer) async throws {
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
        try await waitForCapacity(in: audioSamples)
        guard audioSamples.push(normalization.sampleBuffer) else { return }
        refreshQueueMetrics()
        requestAudioDrain()
        activatePlaybackIfReady()
    }

    private func waitForCapacity(in queue: NativeSampleBufferQueue) async throws {
        while queue.isFull {
            try Task.checkCancellation()
            requestVideoDrain()
            requestAudioDrain()
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

    private func startDrainTimers() {
        stopDrainTimers()
        videoDrainTimer = makeDrainTimer(queue: videoQueue, interval: 1.0 / 60.0) { [weak self] in
            self?.drainVideoQueueNow()
        }
        audioRenderer.requestMediaDataWhenReady(on: audioQueue) { [weak self] in
            self?.drainAudioQueueNow()
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

    private func requestVideoDrain() {
        videoQueue.async { [weak self] in
            self?.drainVideoQueueNow()
        }
    }

    private func requestAudioDrain() {
        audioQueue.async { [weak self] in
            self?.drainAudioQueueNow()
        }
    }

    private func drainVideoQueueNow() {
        while displayLayer.isReadyForMoreMediaData {
            guard let sample = videoSamples.pop() else { break }
            applyPreferredDisplayCriteriaIfNeeded(from: sample)
            displayLayer.enqueue(sample)
            recordVideoSample(sample)
        }
        refreshQueueMetrics()
    }

    private func drainAudioQueueNow() {
        guard !handleAudioRendererFailureIfNeeded() else { return }
        var hadAudio = false
        while audioRenderer.isReadyForMoreMediaData {
            guard let sample = audioSamples.pop() else { break }
            hadAudio = true
            audioRenderer.enqueue(sample)
            recordAudioSample(sample)
            if handleAudioRendererFailureIfNeeded() { return }
        }
        refreshQueueMetrics()
        if !hadAudio, audioRenderer.isReadyForMoreMediaData, isRunningPlayback(), isAudioStarved() {
            recordAudioStarvationIfNeeded()
        } else {
            resetAudioStarvation()
            activatePlaybackIfReady()
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

    private func activatePlaybackIfReady() {
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

    private func handleAudioRendererFailureIfNeeded() -> Bool {
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
        activatePlaybackIfReady()
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

    private func recordVideoSample(_ sample: CMSampleBuffer) {
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
        activatePlaybackIfReady()
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

    private func recordAudioSample(_ sample: CMSampleBuffer) {
        let sampleCount = CMSampleBufferGetNumSamples(sample)
        updateMetrics {
            $0.audioPacketCount += 1
            $0.audioRenderedSampleCount += sampleCount
            $0.maxAudioSamplesPerBuffer = max($0.maxAudioSamplesPerBuffer, sampleCount)
            $0.audioPrimedPacketCount += 1
            $0.audioPTS = CMSampleBufferGetPresentationTimeStamp(sample).matroskaSafeSeconds
        }
        activatePlaybackIfReady()
    }

    private func recordSubtitlePacket(_ packet: MediaPacket) {
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
            self?.subtitleCues.append(cue)
            self?.renderActiveSubtitles()
        }
    }

    private func updateMetrics(_ update: (inout NativeMatroskaSampleBufferMetrics) -> Void) {
        metricsLock.lock()
        update(&metrics)
        metricsLock.unlock()
    }

    private func publishDiagnostics() {
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
            self?.onPlaybackTime?(snapshot.playbackTime)
            self?.onDiagnostics?(snapshot.overlayLines(base: self?.baseDiagnostics ?? []))
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
