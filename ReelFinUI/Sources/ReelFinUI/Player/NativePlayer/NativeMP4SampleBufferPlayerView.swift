import AVFoundation
import AVKit
import NativeMediaCore
import Shared
import SwiftUI
import UIKit

struct NativeMP4SampleBufferPlayerView: UIViewControllerRepresentable {
    let url: URL
    let startTimeSeconds: Double
    let seekRequest: NativePlayerSeekRequest?
    let baseDiagnostics: [String]
    @Binding var isPaused: Bool
    let onDiagnostics: ([String]) -> Void
    let onPlaybackTime: (Double) -> Void

    func makeUIViewController(context: Context) -> NativeMP4SampleBufferPlayerController {
        let controller = NativeMP4SampleBufferPlayerController()
        controller.configure(
            url: url,
            startTimeSeconds: startTimeSeconds,
            seekRequest: seekRequest,
            baseDiagnostics: baseDiagnostics,
            isPaused: isPaused,
            onDiagnostics: onDiagnostics,
            onPlaybackTime: onPlaybackTime
        )
        return controller
    }

    func updateUIViewController(_ controller: NativeMP4SampleBufferPlayerController, context: Context) {
        controller.configure(
            url: url,
            startTimeSeconds: startTimeSeconds,
            seekRequest: seekRequest,
            baseDiagnostics: baseDiagnostics,
            isPaused: isPaused,
            onDiagnostics: onDiagnostics,
            onPlaybackTime: onPlaybackTime
        )
    }

    static func dismantleUIViewController(_ controller: NativeMP4SampleBufferPlayerController, coordinator: ()) {
        controller.stopForDismantle()
    }
}

final class NativeMP4SampleBufferPlayerController: UIViewController {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let audioRenderer = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let videoQueue = DispatchQueue(label: "reelfin.nativeplayer.mp4.video", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "reelfin.nativeplayer.mp4.audio", qos: .userInitiated)
    private let metricsLock = NSLock()

    private var currentURL: URL?
    private var currentStartTimeSeconds: Double = 0
    private var appliedSeekRequestID: Int?
    private var baseDiagnostics: [String] = []
    private var onDiagnostics: (([String]) -> Void)?
    private var onPlaybackTime: ((Double) -> Void)?
    private var openTask: Task<Void, Never>?
    private var reader: AVAssetReader?
    private var videoOutput: AVAssetReaderTrackOutput?
    private var audioOutput: AVAssetReaderTrackOutput?
    private var readableURL: AVFoundationReadableMediaURL?
    private var diagnosticTimer: Timer?
    private var metrics = NativeMP4SampleBufferMetrics()
    private var pendingPause = false
    private var pauseStateGate = NativePauseStateGate()
    private var isTornDown = false
#if os(tvOS)
    private lazy var displayCriteriaCoordinator = NativeDisplayCriteriaCoordinator(viewController: self)
#endif
    private(set) var playbackGeneration = 0
    private(set) var pauseStateApplicationCount = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
        view.layer.addSublayer(displayLayer)
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
        startTimeSeconds: Double,
        seekRequest: NativePlayerSeekRequest?,
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
        if currentURL != url {
            currentURL = url
            currentStartTimeSeconds = startTimeSeconds
            appliedSeekRequestID = seekRequest?.id
            startPlayback(url: url, startTimeSeconds: startTimeSeconds)
        } else if let seekRequest, appliedSeekRequestID != seekRequest.id {
            appliedSeekRequestID = seekRequest.id
            startPlayback(url: url, startTimeSeconds: seekRequest.targetSeconds)
        }
        setPaused(isPaused)
        publishDiagnostics()
    }

    private func startPlayback(url: URL, startTimeSeconds: Double) {
        stopPlayback(publishFinalPlaybackTime: false)
        playbackGeneration += 1
        pauseStateGate.reset()
        currentURL = url
        currentStartTimeSeconds = startTimeSeconds
        updateMetrics { $0 = NativeMP4SampleBufferMetrics() }
        updateMetrics { $0.state = "openingAsset" }
        diagnosticTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.publishDiagnostics()
        }
        openTask = Task { [weak self] in
            await self?.openAssetAndStart(url: url, startTimeSeconds: startTimeSeconds)
        }
    }

    private func stopPlayback(publishFinalPlaybackTime: Bool = true) {
        let finalPlaybackTime = synchronizer.currentTime().safeSeconds
        if publishFinalPlaybackTime, !isTornDown, let onPlaybackTime {
            DispatchQueue.main.async {
                onPlaybackTime(finalPlaybackTime)
            }
        }
        openTask?.cancel()
        openTask = nil
        diagnosticTimer?.invalidate()
        diagnosticTimer = nil
        displayLayer.stopRequestingMediaData()
        audioRenderer.stopRequestingMediaData()
        displayLayer.flushAndRemoveImage()
        audioRenderer.flush()
        reader?.cancelReading()
        reader = nil
        videoOutput = nil
        audioOutput = nil
        readableURL = nil
        resetPreferredDisplayCriteria()
        pauseStateGate.reset()
    }

    private func openAssetAndStart(url: URL, startTimeSeconds: Double) async {
        do {
            AppLog.playback.notice("nativeplayer.sampleReader.start — backend=AVAssetReader")
            let readableURL = try AVFoundationReadableMediaURL(originalURL: url, format: .mp4)
            self.readableURL = readableURL
            let asset = AVURLAsset(url: readableURL.assetURL)
            let tracks = try await asset.load(.tracks)
            let duration = try await asset.load(.duration)
            let videoHDRMetadata: HDRMetadata?
            do {
                videoHDRMetadata = try await Self.hdrMetadata(from: tracks.first(where: { $0.mediaType == .video }))
            } catch {
                videoHDRMetadata = nil
            }
            let reader = try AVAssetReader(asset: asset)
            applyStartTime(startTimeSeconds, duration: duration, to: reader)
            try addOutputs(to: reader, tracks: tracks)
            guard reader.startReading() else {
                throw NativeMP4SampleBufferPlayerError.readerStart(reader.error?.localizedDescription ?? "unknown")
            }
            self.reader = reader
            updateMetrics { metrics in
                metrics.state = pendingPause ? "paused" : "playing"
                metrics.videoDecoderBackend = "AVAssetReader compressed samples"
                metrics.audioDecoderBackend = "AVSampleBufferAudioRenderer"
                metrics.startTime = startTimeSeconds
                metrics.hdrFormat = videoHDRMetadata?.format.rawValue ?? "unknown"
                metrics.dolbyVisionProfile = videoHDRMetadata?.dolbyVision?.profile.map(String.init) ?? "none"
            }
            startClock(at: startTimeSeconds, paused: pendingPause)
            startVideoPump()
            startAudioPump()
        } catch {
            updateMetrics {
                $0.state = "failed"
                $0.failure = error.localizedDescription
            }
            publishDiagnostics()
        }
    }

    private func addOutputs(to reader: AVAssetReader, tracks: [AVAssetTrack]) throws {
        if let videoTrack = tracks.first(where: { $0.mediaType == .video }) {
            let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { throw NativeMP4SampleBufferPlayerError.cannotAddVideoOutput }
            reader.add(output)
            videoOutput = output
        }
        if let audioTrack = tracks.first(where: { $0.mediaType == .audio }) {
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { throw NativeMP4SampleBufferPlayerError.cannotAddAudioOutput }
            reader.add(output)
            audioOutput = output
        }
        guard videoOutput != nil || audioOutput != nil else {
            throw NativeMP4SampleBufferPlayerError.noPlayableTracks
        }
    }

    private func applyStartTime(_ seconds: Double, duration: CMTime, to reader: AVAssetReader) {
        guard seconds > 0, duration.isValid else { return }
        let start = CMTime(seconds: seconds, preferredTimescale: 600)
        let remaining = CMTimeSubtract(duration, start)
        guard remaining.isValid, remaining > .zero else { return }
        reader.timeRange = CMTimeRange(start: start, duration: remaining)
    }

    private func startVideoPump() {
        guard let videoOutput else { return }
        AppLog.playback.notice("nativeplayer.videoRenderer.start — backend=AVSampleBufferDisplayLayer")
        displayLayer.requestMediaDataWhenReady(on: videoQueue) { [weak self] in
            guard let self else { return }
            while self.displayLayer.isReadyForMoreMediaData {
                guard let sample = videoOutput.copyNextSampleBuffer() else {
                    self.displayLayer.stopRequestingMediaData()
                    self.markEndedIfReaderFinished()
                    return
                }
                let start = CACurrentMediaTime()
                self.applyPreferredDisplayCriteriaIfNeeded(from: sample)
                self.displayLayer.enqueue(sample)
                self.recordVideoSample(sample, renderLatencyMs: (CACurrentMediaTime() - start) * 1000)
            }
        }
    }

    private func startAudioPump() {
        guard let audioOutput else { return }
        AppLog.playback.notice("nativeplayer.audioRenderer.start — backend=AVSampleBufferAudioRenderer")
        audioRenderer.requestMediaDataWhenReady(on: audioQueue) { [weak self] in
            guard let self else { return }
            while self.audioRenderer.isReadyForMoreMediaData {
                guard let sample = audioOutput.copyNextSampleBuffer() else {
                    self.audioRenderer.stopRequestingMediaData()
                    self.markEndedIfReaderFinished()
                    return
                }
                self.audioRenderer.enqueue(sample)
                self.recordAudioSample(sample)
            }
        }
    }

    private func setPaused(_ paused: Bool) {
        guard pauseStateGate.shouldApply(paused) else { return }
        pauseStateApplicationCount += 1
        let time = synchronizer.currentTime()
        synchronizer.setRate(paused ? 0 : 1, time: time)
        updateMetrics { $0.state = paused ? "paused" : "playing" }
    }

    private func startClock(at seconds: Double, paused: Bool) {
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        synchronizer.setRate(paused ? 0 : 1, time: time)
        pauseStateGate.markApplied(paused)
        updateMetrics { $0.state = paused ? "paused" : "playing" }
    }

    private func recordVideoSample(_ sample: CMSampleBuffer, renderLatencyMs: Double) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        let metadata = HDRCoreMediaMapper.metadata(from: CMSampleBufferGetFormatDescription(sample))
        updateMetrics {
            $0.videoPacketCount += 1
            $0.currentPTS = pts.safeSeconds
            $0.renderLatencyMs = renderLatencyMs
            $0.droppedFrames = displayLayer.status == .failed ? $0.droppedFrames + 1 : $0.droppedFrames
            if let metadata {
                $0.hdrFormat = metadata.format.rawValue
                $0.dolbyVisionProfile = metadata.dolbyVision?.profile.map(String.init) ?? "none"
            }
        }
    }

    private static func hdrMetadata(from track: AVAssetTrack?) async throws -> HDRMetadata? {
        guard
            let track,
            let formatDescription = try await track.load(.formatDescriptions).first
        else { return nil }
        let codec = CMFormatDescriptionGetMediaSubType(formatDescription)
        return HDRCoreMediaMapper.metadata(
            from: formatDescription,
            codecFourCC: fourCC(codec)
        )
    }

    private static func fourCC(_ value: FourCharCode) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? "\(value)"
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
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        updateMetrics {
            $0.audioPacketCount += 1
            $0.audioPTS = pts.safeSeconds
        }
    }

    private func markEndedIfReaderFinished() {
        guard reader?.status == .completed else { return }
        updateMetrics { $0.state = "ended" }
        publishDiagnostics()
    }

    private func updateMetrics(_ update: (inout NativeMP4SampleBufferMetrics) -> Void) {
        metricsLock.lock()
        update(&metrics)
        metricsLock.unlock()
    }

    private func publishDiagnostics() {
        metricsLock.lock()
        var snapshot = metrics
        metricsLock.unlock()
        snapshot.playbackTime = synchronizer.currentTime().safeSeconds
        let lines = snapshot.overlayLines(base: baseDiagnostics)
        DispatchQueue.main.async { [weak self] in
            self?.onPlaybackTime?(snapshot.playbackTime)
            self?.onDiagnostics?(lines)
        }
    }
}

private enum NativeMP4SampleBufferPlayerError: LocalizedError {
    case noPlayableTracks
    case cannotAddVideoOutput
    case cannotAddAudioOutput
    case readerStart(String)

    var errorDescription: String? {
        switch self {
        case .noPlayableTracks:
            return "MP4 AVAssetReader found no playable audio or video tracks."
        case .cannotAddVideoOutput:
            return "MP4 AVAssetReader could not add compressed video output."
        case .cannotAddAudioOutput:
            return "MP4 AVAssetReader could not add compressed audio output."
        case .readerStart(let reason):
            return "MP4 AVAssetReader failed to start: \(reason)"
        }
    }
}

private struct NativeMP4SampleBufferMetrics {
    var state = "idle"
    var videoPacketCount = 0
    var audioPacketCount = 0
    var droppedFrames = 0
    var renderLatencyMs: Double = 0
    var currentPTS: Double = 0
    var audioPTS: Double = 0
    var playbackTime: Double = 0
    var startTime: Double = 0
    var videoDecoderBackend = "none"
    var audioDecoderBackend = "none"
    var hdrFormat = "unknown"
    var dolbyVisionProfile = "none"
    var failure: String?

    func overlayLines(base: [String]) -> [String] {
        var lines = base.filter { !$0.hasPrefix("state=") && !$0.hasPrefix("packets ") }
        lines.insert("state=\(state)", at: 0)
        lines.append("packets video=\(videoPacketCount) audio=\(audioPacketCount)")
        lines.append("videoDecoderBackend=\(videoDecoderBackend)")
        lines.append("audioDecoderBackend=\(audioDecoderBackend)")
        lines.append("rendererBackend=AVSampleBufferDisplayLayer")
        lines.append("audioRendererBackend=AVSampleBufferAudioRenderer")
        lines.append("hdr=\(hdrFormat) dvProfile=\(dolbyVisionProfile)")
        lines.append("masterClock=AVSampleBufferRenderSynchronizer")
        lines.append("startTime=\(String(format: "%.3f", startTime))")
        lines.append("currentPTS=\(String(format: "%.3f", currentPTS)) playbackTime=\(String(format: "%.3f", playbackTime))")
        lines.append("avDriftMs=\(String(format: "%.1f", (currentPTS - audioPTS) * 1000)) renderLatencyMs=\(String(format: "%.1f", renderLatencyMs))")
        lines.append("droppedFrames=\(droppedFrames)")
        if let failure {
            lines.append("failureModule=NativeMP4SampleBufferPlayer failure=\(failure)")
        }
        return lines
    }
}

private extension CMTime {
    var safeSeconds: Double {
        guard isValid && !isIndefinite && !isNegativeInfinity && !isPositiveInfinity else {
            return 0
        }
        return seconds.isFinite ? seconds : 0
    }
}
