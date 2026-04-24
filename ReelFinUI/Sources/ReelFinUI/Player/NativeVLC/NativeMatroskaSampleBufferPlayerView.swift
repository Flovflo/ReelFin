import AVFoundation
import NativeMediaCore
import Shared
import SwiftUI
import UIKit

struct NativeMatroskaSampleBufferPlayerView: UIViewControllerRepresentable {
    let url: URL
    let headers: [String: String]
    let container: ContainerFormat
    let startTimeSeconds: Double
    let baseDiagnostics: [String]
    @Binding var isPaused: Bool
    let onDiagnostics: ([String]) -> Void
    let onPlaybackTime: (Double) -> Void

    func makeUIViewController(context: Context) -> NativeMatroskaSampleBufferPlayerController {
        let controller = NativeMatroskaSampleBufferPlayerController()
        controller.configure(url: url, headers: headers, container: container, startTimeSeconds: startTimeSeconds, baseDiagnostics: baseDiagnostics, isPaused: isPaused, onDiagnostics: onDiagnostics, onPlaybackTime: onPlaybackTime)
        return controller
    }

    func updateUIViewController(_ controller: NativeMatroskaSampleBufferPlayerController, context: Context) {
        controller.configure(url: url, headers: headers, container: container, startTimeSeconds: startTimeSeconds, baseDiagnostics: baseDiagnostics, isPaused: isPaused, onDiagnostics: onDiagnostics, onPlaybackTime: onPlaybackTime)
    }

    static func dismantleUIViewController(_ controller: NativeMatroskaSampleBufferPlayerController, coordinator: ()) {
        controller.stopForDismantle()
    }
}

final class NativeMatroskaSampleBufferPlayerController: UIViewController {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let audioRenderer = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let subtitleOverlay = NativeSubtitleOverlayView()
    private let videoQueue = DispatchQueue(label: "reelfin.nativevlc.mkv.video", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "reelfin.nativevlc.mkv.audio", qos: .userInitiated)
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
    private(set) var playbackGeneration = 0
    private(set) var pauseStateApplicationCount = 0

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
        stopPlayback()
    }

    deinit { stopPlayback() }

    func stopForDismantle() {
        stopPlayback()
    }

    func configure(
        url: URL,
        headers: [String: String],
        container: ContainerFormat,
        startTimeSeconds: Double,
        baseDiagnostics: [String],
        isPaused: Bool,
        onDiagnostics: @escaping ([String]) -> Void,
        onPlaybackTime: @escaping (Double) -> Void
    ) {
        self.baseDiagnostics = baseDiagnostics
        self.onDiagnostics = onDiagnostics
        self.onPlaybackTime = onPlaybackTime
        pendingPause = isPaused
        if currentURL != url || currentHeaders != headers || currentContainer != container {
            currentURL = url
            currentHeaders = headers
            currentContainer = container
            currentStartTimeSeconds = startTimeSeconds
            startPlayback(url: url, headers: headers, container: container, startTimeSeconds: startTimeSeconds)
        }
        setPaused(isPaused)
        publishDiagnostics()
    }

    private func startPlayback(url: URL, headers: [String: String], container: ContainerFormat, startTimeSeconds: Double) {
        stopPlayback()
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
        metricsLock.lock()
        metrics = NativeMatroskaSampleBufferMetrics()
        metricsLock.unlock()
        updateMetrics { $0.state = "openingByteSource" }
        diagnosticTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.publishDiagnostics()
        }
        playbackTask = Task { [weak self] in
            await self?.openDemuxAndPump(url: url, headers: headers, container: container, startTimeSeconds: startTimeSeconds)
        }
    }

    private func stopPlayback() {
        let finalPlaybackTime = synchronizer.currentTime().matroskaSafeSeconds
        if let onPlaybackTime {
            if Thread.isMainThread {
                onPlaybackTime(finalPlaybackTime)
            } else {
                DispatchQueue.main.async {
                    onPlaybackTime(finalPlaybackTime)
                }
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
        playbackStateLock.lock()
        playbackCanRun = false
        rebufferingForAudio = false
        consecutiveAudioStarvationTicks = 0
        reportedAudioStarvation = false
        lastBufferWaitLogTime = 0
        audioRendererFailureReported = false
        audioStartupDegraded = false
        audioStartupWatchdog.reset()
        audioStarvationGate.reset()
        playbackStateLock.unlock()
        pauseStateGate.reset()
    }

    private func openDemuxAndPump(url: URL, headers: [String: String], container: ContainerFormat, startTimeSeconds: Double) async {
        do {
            AppLog.playback.notice("nativevlc.sampleReader.start — backend=\(Self.demuxerName(for: container), privacy: .public)")
            let source = HTTPRangeByteSource(url: url, headers: headers)
            let demuxer = Self.makeDemuxer(source: source, container: container)
            let stream = try await demuxer.open()
            if startTimeSeconds > 0 {
                try await demuxer.seek(to: CMTime(seconds: startTimeSeconds, preferredTimescale: 1000))
            }
            guard let videoTrack = stream.tracks.first(where: { $0.kind == .video }) else {
                throw NativeMatroskaSampleBufferPlayerError.noVideoTrack
            }
            let audioTrack = stream.tracks.first(where: { $0.kind == .audio })
            let subtitleTrack = stream.tracks.first(where: { $0.kind == .subtitle && Self.canRenderSubtitle($0) })
            let videoDecoder = try VideoDecoderFactory().makeDecoder(for: videoTrack)
            try await videoDecoder.configure(track: videoTrack)
            let audioDecoder = await makeAudioDecoder(audioTrack)
            resetPlaybackReadiness(hasAudio: audioDecoder != nil)

            updateMetrics {
                $0.state = pendingPause ? "paused" : "buffering"
                $0.videoDecoderBackend = "VideoToolbox"
                $0.audioDecoderBackend = audioDecoder == nil ? "none" : "AppleAudioToolbox"
                $0.startTime = startTimeSeconds
            }
            AppLog.playback.notice("nativevlc.videoRenderer.start — backend=AVSampleBufferDisplayLayer")
            AppLog.playback.notice("nativevlc.audioRenderer.start — backend=AVSampleBufferAudioRenderer")
            startClock(at: startTimeSeconds, paused: true)
            startDrainTimers()
            try await pumpPackets(
                demuxer: demuxer,
                videoTrack: videoTrack,
                audioTrack: audioTrack,
                subtitleTrack: subtitleTrack,
                videoDecoder: videoDecoder,
                audioDecoder: audioDecoder
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
        audioDecoder: (any AudioDecoder)?
    ) async throws {
        while !Task.isCancelled, let packet = try await demuxer.readNextPacket() {
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
            AppLog.playback.warning("nativevlc.audio.starvation — elapsed=\(decision.elapsedSeconds, privacy: .public) ticks=\(decision.ticks, privacy: .public)")
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
            AppLog.playback.error("nativevlc.audio.startup_degraded — videoPackets=\(snapshot.videoPacketCount) audioPackets=\(snapshot.audioPacketCount) audioPrimed=\(snapshot.audioPrimedPacketCount) audioAhead=\(decision.audioAheadSeconds, privacy: .public)")
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
        AppLog.playback.notice("nativevlc.buffering.ready — videoPackets=\(snapshot.videoPacketCount) audioPackets=\(snapshot.audioPacketCount) audioPrimed=\(snapshot.audioPrimedPacketCount) requiredAudioPrimed=\(decision.requiredAudioPrimedPacketCount) audioAhead=\(decision.audioAheadSeconds, privacy: .public) videoAhead=\(decision.videoAheadSeconds, privacy: .public)")
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
            AppLog.playback.error("nativevlc.audioRenderer.failed — \(message, privacy: .public)")
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
        AppLog.playback.notice("nativevlc.buffering.wait — videoPackets=\(snapshot.videoPacketCount) audioPackets=\(snapshot.audioPacketCount) audioPrimed=\(snapshot.audioPrimedPacketCount) requiredAudioPrimed=\(decision.requiredAudioPrimedPacketCount) needsAudio=\(needsAudio, privacy: .public) audioAhead=\(decision.audioAheadSeconds, privacy: .public) requiredAudioAhead=\(decision.requiredAudioAheadSeconds, privacy: .public) videoAhead=\(decision.videoAheadSeconds, privacy: .public) requiredVideoAhead=\(decision.requiredVideoAheadSeconds, privacy: .public)")
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
        updateMetrics {
            $0.videoPacketCount += 1
            $0.videoPrimedPacketCount += 1
            $0.currentPTS = CMSampleBufferGetPresentationTimeStamp(sample).matroskaSafeSeconds
            $0.droppedFrames = displayLayer.status == .failed ? $0.droppedFrames + 1 : $0.droppedFrames
        }
        activatePlaybackIfReady()
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
