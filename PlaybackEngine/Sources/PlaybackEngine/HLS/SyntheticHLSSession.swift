import Foundation
import CoreMedia
import Shared

public enum SyntheticHLSError: Error, LocalizedError {
    case notPrepared
    case endOfStream
    case missingSegment(Int)

    public var errorDescription: String? {
        switch self {
        case .notPrepared:
            return "Synthetic HLS session is not prepared"
        case .endOfStream:
            return "Demuxer reached end of stream"
        case .missingSegment(let sequence):
            return "Segment \(sequence) is unavailable"
        }
    }
}

public actor SegmentCacheActor {
    private let maxBytes: Int
    private var storage: [Int: Data] = [:]
    private var order: [Int] = []
    private var currentBytes: Int = 0

    public init(maxBytes: Int = 16 * 1024 * 1024) {
        self.maxBytes = max(1_048_576, maxBytes)
    }

    public func data(for sequence: Int) -> Data? {
        guard let value = storage[sequence] else { return nil }
        touch(sequence)
        return value
    }

    public func put(_ data: Data, for sequence: Int) {
        if let old = storage[sequence] {
            currentBytes -= old.count
        }
        storage[sequence] = data
        touch(sequence)
        currentBytes += data.count
        evictIfNeeded()
    }

    public func invalidateForSeek(targetPTS: Int64) {
        _ = targetPTS
        storage.removeAll()
        order.removeAll()
        currentBytes = 0
    }

    private func touch(_ sequence: Int) {
        order.removeAll(where: { $0 == sequence })
        order.append(sequence)
    }

    private func evictIfNeeded() {
        while currentBytes > maxBytes, let oldest = order.first {
            order.removeFirst()
            if let removed = storage.removeValue(forKey: oldest) {
                currentBytes -= removed.count
            }
        }
    }
}

public actor PackagingSchedulerActor {
    private let demuxer: Demuxer
    private let repackager: Repackager
    private let videoTrackID: Int
    private let audioTrackID: Int?
    private let allowedTrackIDs: Set<Int>
    private let targetDurationSeconds: Double
    private let startupTargetDurationSeconds: Double
    private let startupMaxSamples: Int

    private var nextSequenceToGenerate: Int = 0
    private var generatedSegments: [Int: Data] = [:]
    private var segmentDurations: [Int: Double] = [:]

    public init(
        demuxer: Demuxer,
        repackager: Repackager,
        videoTrackID: Int,
        audioTrackID: Int? = nil,
        targetDurationSeconds: Double = 3.0,
        startupTargetDurationSeconds: Double = 1.5,
        startupMaxSamples: Int = 64
    ) {
        self.demuxer = demuxer
        self.repackager = repackager
        self.videoTrackID = videoTrackID
        self.audioTrackID = audioTrackID
        self.allowedTrackIDs = Set([videoTrackID, audioTrackID].compactMap { $0 })
        self.targetDurationSeconds = max(1.0, targetDurationSeconds)
        self.startupTargetDurationSeconds = max(0.5, min(self.targetDurationSeconds, startupTargetDurationSeconds))
        self.startupMaxSamples = max(8, startupMaxSamples)
    }

    public func segment(for sequence: Int) async throws -> Data {
        if let cached = generatedSegments[sequence] {
            return cached
        }

        while nextSequenceToGenerate <= sequence {
            let generatedSequence = nextSequenceToGenerate
            let samples = try await collectSegmentSamples(sequence: generatedSequence)
            guard !samples.isEmpty else {
                throw SyntheticHLSError.endOfStream
            }
            let fragment = try await repackager.generateFragment(samples: samples)
            let durationNs = samples.reduce(Int64(0)) { $0 + max(0, $1.durationNanoseconds) }
            let durationSeconds = max(0.001, Double(durationNs) / 1_000_000_000.0)
            generatedSegments[generatedSequence] = fragment
            segmentDurations[generatedSequence] = durationSeconds
            if generatedSequence == 0 {
                AppLog.nativeBridge.notice(
                    "[NB-DIAG] hls.startup.segment-built — samples=\(samples.count, privacy: .public) duration=\(durationSeconds, format: .fixed(precision: 3))s bytes=\(fragment.count, privacy: .public)"
                )
            }
            nextSequenceToGenerate += 1
        }

        guard let data = generatedSegments[sequence] else {
            throw SyntheticHLSError.missingSegment(sequence)
        }
        return data
    }

    public func duration(for sequence: Int) -> Double? {
        segmentDurations[sequence]
    }

    public func generatedSequences() -> [Int] {
        generatedSegments.keys.sorted()
    }

    public func invalidateAfterSeek() {
        nextSequenceToGenerate = 0
        generatedSegments.removeAll()
        segmentDurations.removeAll()
    }

    private func collectSegmentSamples(sequence: Int) async throws -> [Sample] {
        var samples: [Sample] = []
        var durationNs: Int64 = 0
        let isStartupSegment = (sequence == 0)
        let targetNs = Int64((isStartupSegment ? startupTargetDurationSeconds : targetDurationSeconds) * 1_000_000_000.0)
        let startupAudioGraceNs: Int64 = 400_000_000
        let startupAudioGraceSamples = 24
        let requiresAudioForStartup = isStartupSegment && (audioTrackID != nil)
        var sawVideoKeyframeBoundary = false
        var sawVideoSample = false
        var sawAudioSample = false

        while true {
            guard let sample = try await demuxer.readSample() else { break }
            guard allowedTrackIDs.contains(sample.trackID) else { continue }

            samples.append(sample)
            durationNs += max(0, sample.durationNanoseconds)

            if sample.trackID == videoTrackID {
                sawVideoSample = true
                if sample.isKeyframe, samples.count > 1 {
                    sawVideoKeyframeBoundary = true
                }
            } else if sample.trackID == audioTrackID {
                sawAudioSample = true
            }

            if isStartupSegment {
                let reachedSoftStartupLimit = durationNs >= targetNs || samples.count >= startupMaxSamples

                if requiresAudioForStartup, !sawAudioSample {
                    let exceededAudioWait =
                        durationNs >= (targetNs + startupAudioGraceNs) ||
                        samples.count >= (startupMaxSamples + startupAudioGraceSamples)
                    if exceededAudioWait {
                        break
                    }
                    continue
                }

                if reachedSoftStartupLimit, sawVideoSample {
                    break
                }
            } else {
                if durationNs >= targetNs, sawVideoKeyframeBoundary {
                    break
                }

                if samples.count >= 160 {
                    break
                }
            }
        }

        return samples
    }
}

public actor SyntheticHLSSession {
    private static let minimumPreloadSegments = 3
    private static let playlistGrowthStepSegments = 2

    private let plan: NativeBridgePlan
    private let demuxer: Demuxer
    private let repackager: Repackager
    private let manifestBuilder = HLSManifestBuilder()
    private let timelineBuilder = CMAFSegmentTimelineBuilder()
    private let cache: SegmentCacheActor
    private let scheduler: PackagingSchedulerActor
    private let defaultPreloadCount: Int

    /// Explicit packaging mode requested by caller (default: dvProfile81Compatible).
    private let requestedPackagingMode: DolbyVisionPackagingMode

    private var streamInfo: StreamInfo?
    private var initSegmentData: Data?
    private var initSegmentInspection: InitSegmentInspection?
    /// The resolved packaging decision (set during prepare()).
    private var packagingDecision: NativeBridgePackagingDecision?
    private var reachedEndOfStream = false
    private var prefetchInFlight = false
    private var prefetchTargetSequence = 0

    public init(
        plan: NativeBridgePlan,
        demuxer: Demuxer,
        repackager: Repackager,
        cache: SegmentCacheActor = SegmentCacheActor(),
        defaultPreloadCount: Int = 3,
        packagingMode: DolbyVisionPackagingMode = NativeBridgeDebugToggles.packagingMode
    ) {
        self.plan = plan
        self.demuxer = demuxer
        self.repackager = repackager
        self.cache = cache
        self.defaultPreloadCount = max(Self.minimumPreloadSegments, defaultPreloadCount)
        self.requestedPackagingMode = packagingMode
        self.scheduler = PackagingSchedulerActor(
            demuxer: demuxer,
            repackager: repackager,
            videoTrackID: plan.videoTrack.id,
            audioTrackID: plan.audioTrack?.id,
            targetDurationSeconds: 3
        )
    }

    public func prepare() async throws {
        let opened = try await demuxer.open()
        streamInfo = opened

        // Evaluate packaging decision based on mode, plan, stream, and device
        let device = DeviceCapabilityFingerprint.current()
        let decision = DolbyVisionGate.evaluatePackaging(
            plan: plan,
            streamInfo: opened,
            device: device,
            requestedMode: requestedPackagingMode
        )
        packagingDecision = decision
        AppLog.nativeBridge.notice(
            "[NB-DIAG] hls.packaging.decision — mode=\(decision.mode.rawValue, privacy: .public) entry=\(decision.videoEntry.sampleEntryType, privacy: .public) codecs=\(decision.hlsSignaling.codecs, privacy: .public) supplemental=\(decision.hlsSignaling.supplementalCodecs ?? "none", privacy: .public) videoRange=\(decision.hlsSignaling.videoRange ?? "none", privacy: .public) reason=\(decision.reason, privacy: .public)"
        )

        // Push the decision to the repackager BEFORE init segment generation
        await repackager.setPackagingDecision(decision)

        let initData = try await repackager.generateInitSegment(streamInfo: opened)
        initSegmentData = initData
        initSegmentInspection = InitSegmentInspector.inspect(initData)
        if let inspection = initSegmentInspection {
            AppLog.nativeBridge.notice(
                "[NB-DIAG] hls.init.inspection — hvcC=\(inspection.hasHvcC, privacy: .public) dvcC=\(inspection.hasDvcC, privacy: .public) dvvC=\(inspection.hasDvvC, privacy: .public) videoEntry=\(inspection.videoSampleEntry ?? "unknown", privacy: .public) audioEntry=\(inspection.audioSampleEntry ?? "unknown", privacy: .public) inferred=\(inspection.inferredMode.rawValue, privacy: .public)"
            )
        }
        reachedEndOfStream = false
        prefetchInFlight = false
        prefetchTargetSequence = 0
        _ = try await scheduler.segment(for: 0)
    }

    public func initSegment() async throws -> Data {
        guard let initSegmentData else {
            throw SyntheticHLSError.notPrepared
        }
        return initSegmentData
    }

    public func segment(sequence: Int) async throws -> Data {
        if let cached = await cache.data(for: sequence) {
            return cached
        }
        let data = try await scheduler.segment(for: sequence)
        await cache.put(data, for: sequence)
        return data
    }

    public func masterPlaylist(baseURL: URL? = nil) async throws -> String {
        guard let info = streamInfo, let decision = packagingDecision else {
            throw SyntheticHLSError.notPrepared
        }
        let resolution = "\(info.primaryVideoTrack?.width ?? 1920)x\(info.primaryVideoTrack?.height ?? 1080)"
        let hls = decision.hlsSignaling
        let videoPlaylistURI = absoluteURI(path: "video.m3u8", relativeTo: baseURL)
        return manifestBuilder.makeMasterPlaylist(
            videoPlaylistURI: videoPlaylistURI,
            subtitlePlaylistURI: nil,
            codecs: hls.codecs,
            supplementalCodecs: hls.supplementalCodecs,
            videoRange: hls.videoRange,
            resolution: resolution,
            bandwidth: 20_000_000,
            averageBandwidth: 20_000_000,
            frameRate: hls.frameRate
        )
    }

    public func mediaPlaylist(
        preloadCount: Int? = nil,
        baseURL: URL? = nil,
        startupPreflightSnapshot: Bool = false
    ) async throws -> String {
        guard streamInfo != nil else {
            throw SyntheticHLSError.notPrepared
        }

        var sequences = await scheduler.generatedSequences()
        if sequences.isEmpty {
            do {
                _ = try await segment(sequence: 0)
                sequences = await scheduler.generatedSequences()
            } catch SyntheticHLSError.endOfStream {
                reachedEndOfStream = true
            }
        }

        if !reachedEndOfStream, !startupPreflightSnapshot {
            let baselineCount = max(Self.minimumPreloadSegments, preloadCount ?? defaultPreloadCount)
            let desiredSegmentCount = max(baselineCount, sequences.count + Self.playlistGrowthStepSegments)
            let desiredLastSequence = max(0, desiredSegmentCount - 1)
            requestPrefetch(upTo: desiredLastSequence)
        }

        sequences = await scheduler.generatedSequences()
        var segments: [HLSMediaPlaylistSegment] = []
        segments.reserveCapacity(sequences.count)

        for sequence in sequences {
            let duration = await scheduler.duration(for: sequence) ?? 3.0
            let segmentURI = absoluteURI(path: "segment_\(sequence).m4s", relativeTo: baseURL)
            segments.append(HLSMediaPlaylistSegment(uri: segmentURI, duration: duration))
        }

        if startupPreflightSnapshot {
            let firstSequence = sequences.first ?? 0
            let firstDuration = await scheduler.duration(for: firstSequence) ?? 3.0
            let firstSegmentURI = absoluteURI(path: "segment_\(firstSequence).m4s", relativeTo: baseURL)
            segments = [
                HLSMediaPlaylistSegment(uri: firstSegmentURI, duration: firstDuration)
            ]
        }

        let syntheticSamples = segments.enumerated().map { index, segment in
            Sample(
                trackID: plan.videoTrack.id,
                pts: CMTime(value: Int64(index) * 3_000_000_000, timescale: 1_000_000_000),
                duration: CMTime(seconds: segment.duration, preferredTimescale: 1_000_000_000),
                isKeyframe: true,
                data: Data()
            )
        }
        let timeline = timelineBuilder.build(samples: syntheticSamples, targetDurationSeconds: 3)

        return manifestBuilder.makeMediaPlaylist(
            targetDuration: timeline.targetDurationSeconds,
            mediaSequence: 0,
            initSegmentURI: absoluteURI(path: "init.mp4", relativeTo: baseURL),
            segments: segments,
            endList: startupPreflightSnapshot || reachedEndOfStream
        )
    }

    public func invalidateForSeek(targetPTS: Int64) async throws {
        _ = try await demuxer.seek(to: targetPTS)
        await cache.invalidateForSeek(targetPTS: targetPTS)
        await scheduler.invalidateAfterSeek()
        reachedEndOfStream = false
        prefetchInFlight = false
        prefetchTargetSequence = 0
    }

    private func requestPrefetch(upTo sequence: Int) {
        guard !reachedEndOfStream else { return }
        prefetchTargetSequence = max(prefetchTargetSequence, sequence)
        guard !prefetchInFlight else { return }

        prefetchInFlight = true
        let session = self
        Task.detached(priority: .utility) {
            await session.runPrefetchLoop()
        }
    }

    private func runPrefetchLoop() async {
        while true {
            if reachedEndOfStream {
                prefetchInFlight = false
                return
            }

            let generated = await scheduler.generatedSequences()
            let next = (generated.last ?? -1) + 1
            let target = prefetchTargetSequence
            if next > target {
                prefetchInFlight = false
                return
            }

            do {
                _ = try await segment(sequence: next)
            } catch SyntheticHLSError.endOfStream {
                reachedEndOfStream = true
                prefetchInFlight = false
                return
            } catch {
                AppLog.nativeBridge.warning(
                    "[NB-DIAG] hls.prefetch.failed — sequence=\(next, privacy: .public) reason=\(error.localizedDescription, privacy: .public)"
                )
                prefetchInFlight = false
                return
            }
        }
    }

    private func absoluteURI(path: String, relativeTo baseURL: URL?) -> String {
        guard let baseURL else { return path }
        return baseURL.appendingPathComponent(path).absoluteString
    }
}
