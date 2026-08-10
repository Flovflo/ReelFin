import Foundation
import CoreMedia
import Shared

public enum SyntheticHLSError: Error, LocalizedError {
    case notPrepared
    case endOfStream
    case missingSegment(Int)
    case unsupportedCodecConfiguration(String)
    case independentBoundaryUnavailable(sequence: Int, samplesScanned: Int)

    public var errorDescription: String? {
        switch self {
        case .notPrepared:
            return "Synthetic HLS session is not prepared"
        case .endOfStream:
            return "Demuxer reached end of stream"
        case .missingSegment(let sequence):
            return "Segment \(sequence) is unavailable"
        case .unsupportedCodecConfiguration(let reason):
            return reason
        case .independentBoundaryUnavailable(let sequence, let samplesScanned):
            return "Independent segment boundary unavailable for segment \(sequence) after \(samplesScanned) samples"
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
    private let maximumSegmentBytes: Int
    private let maximumBoundarySearchDurationNs: Int64
    // 4,096 demux reads covers well beyond a normal 60 fps video + packetized
    // audio GOP while the 64 MiB / 12 s limits remain the primary hard bounds.
    private let nonStartupMaxSamples = 4_096
    private let startupAudioGraceNs: Int64 = 400_000_000

    private var nextSequenceToGenerate: Int = 0
    private var generatedSegments: [Int: Data] = [:]
    private var segmentDurations: [Int: Double] = [:]
    private var pendingBoundarySample: Sample?

    public init(
        demuxer: Demuxer,
        repackager: Repackager,
        videoTrackID: Int,
        audioTrackID: Int? = nil,
        targetDurationSeconds: Double = 3.0,
        startupTargetDurationSeconds: Double = 1.5,
        startupMaxSamples: Int = 4_096,
        maximumSegmentBytes: Int = 64 * 1024 * 1024,
        maximumBoundarySearchDurationSeconds: Double = 12
    ) {
        self.demuxer = demuxer
        self.repackager = repackager
        self.videoTrackID = videoTrackID
        self.audioTrackID = audioTrackID
        self.allowedTrackIDs = Set([videoTrackID, audioTrackID].compactMap { $0 })
        let normalizedTargetDuration = Self.normalizedSeconds(
            targetDurationSeconds,
            fallback: 3,
            minimum: 1,
            maximum: 3_600
        )
        self.targetDurationSeconds = normalizedTargetDuration
        self.startupTargetDurationSeconds = Self.normalizedSeconds(
            startupTargetDurationSeconds,
            fallback: 1.5,
            minimum: 0.5,
            maximum: normalizedTargetDuration
        )
        self.startupMaxSamples = max(8, startupMaxSamples)
        self.maximumSegmentBytes = max(1_048_576, maximumSegmentBytes)
        let normalizedSearchDuration = Self.normalizedSeconds(
            maximumBoundarySearchDurationSeconds,
            fallback: 12,
            minimum: 1,
            maximum: 86_400
        )
        self.maximumBoundarySearchDurationNs = Int64(normalizedSearchDuration * 1_000_000_000)
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
            let durationNs = samples.reduce(Int64(0)) {
                Self.saturatedAdd($0, max(0, $1.durationNanoseconds))
            }
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
        pendingBoundarySample = nil
    }

    private func collectSegmentSamples(sequence: Int) async throws -> [Sample] {
        var samples: [Sample] = []
        var durationNs: Int64 = 0
        let isStartupSegment = (sequence == 0)
        let targetNs = Int64((isStartupSegment ? startupTargetDurationSeconds : targetDurationSeconds) * 1_000_000_000.0)
        let requiresStartupAudio = isStartupSegment && audioTrackID != nil
        let maximumSamples = isStartupSegment
            ? startupMaxSamples
            : nonStartupMaxSamples
        var sawVideoSample = false
        var sawAudioSample = false
        var scannedSamples = 0
        var scannedBytes = 0
        var scannedDurationNs: Int64 = 0

        if let pendingBoundarySample {
            samples.append(pendingBoundarySample)
            durationNs = Self.saturatedAdd(durationNs, max(0, pendingBoundarySample.durationNanoseconds))
            sawVideoSample = pendingBoundarySample.trackID == videoTrackID
            sawAudioSample = pendingBoundarySample.trackID == audioTrackID
            scannedSamples = 1
            scannedBytes = pendingBoundarySample.data.count
            scannedDurationNs = max(0, pendingBoundarySample.durationNanoseconds)
            self.pendingBoundarySample = nil
        }

        while true {
            guard let sample = try await demuxer.readSample() else { break }
            scannedSamples = Self.saturatedAdd(scannedSamples, 1)
            scannedBytes = Self.saturatedAdd(scannedBytes, sample.data.count)
            scannedDurationNs = Self.saturatedAdd(
                scannedDurationNs,
                max(0, sample.durationNanoseconds)
            )

            let audioRequirementSatisfied = !requiresStartupAudio
                || sawAudioSample
                || durationNs >= Self.saturatedAdd(targetNs, startupAudioGraceNs)
            let searchBudgetReached = scannedSamples >= maximumSamples
                || scannedBytes >= maximumSegmentBytes
                || scannedDurationNs >= maximumBoundarySearchDurationNs

            guard allowedTrackIDs.contains(sample.trackID) else {
                if searchBudgetReached {
                    throw SyntheticHLSError.independentBoundaryUnavailable(
                        sequence: sequence,
                        samplesScanned: scannedSamples
                    )
                }
                continue
            }

            // A generation epoch (startup or post-seek invalidation) may resume before
            // the demuxer reaches a random-access point. Drop dependent leading video
            // samples so the first advertised video sample remains independently sync.
            if sample.trackID == videoTrackID, !sawVideoSample, !sample.isKeyframe {
                if searchBudgetReached {
                    throw SyntheticHLSError.independentBoundaryUnavailable(
                        sequence: sequence,
                        samplesScanned: scannedSamples
                    )
                }
                continue
            }

            // A media segment advertised under EXT-X-INDEPENDENT-SEGMENTS must leave
            // its boundary sync sample for the next segment. Consuming that keyframe
            // here makes the next fragment begin with a dependent P/B frame.
            if sample.trackID == videoTrackID,
               sample.isKeyframe,
               sawVideoSample,
               durationNs >= targetNs,
               audioRequirementSatisfied {
                pendingBoundarySample = sample
                break
            }

            samples.append(sample)
            durationNs = Self.saturatedAdd(durationNs, max(0, sample.durationNanoseconds))

            if sample.trackID == videoTrackID {
                sawVideoSample = true
            } else if sample.trackID == audioTrackID {
                sawAudioSample = true
            }

            if searchBudgetReached {
                throw SyntheticHLSError.independentBoundaryUnavailable(
                    sequence: sequence,
                    samplesScanned: scannedSamples
                )
            }
        }

        if !sawVideoSample, scannedSamples > 0 {
            throw SyntheticHLSError.independentBoundaryUnavailable(
                sequence: sequence,
                samplesScanned: scannedSamples
            )
        }

        return samples
    }

    private static func normalizedSeconds(
        _ value: Double,
        fallback: Double,
        minimum: Double,
        maximum: Double
    ) -> Double {
        let candidate = value.isFinite ? value : fallback
        return min(max(candidate, minimum), maximum)
    }

    private static func saturatedAdd(_ lhs: Int, _ rhs: Int) -> Int {
        guard rhs > 0 else { return lhs }
        return lhs > Int.max - rhs ? Int.max : lhs + rhs
    }

    private static func saturatedAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        guard rhs > 0 else { return lhs }
        return lhs > Int64.max - rhs ? Int64.max : lhs + rhs
    }
}

public actor SyntheticHLSSession {
    private static let minimumPreloadSegments = 3
    private static let defaultPlaylistGrowthStepSegments = 2

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
    private var adaptivePreloadCount: Int
    private var adaptiveLookaheadSegments: Int

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
        self.adaptivePreloadCount = max(Self.minimumPreloadSegments, defaultPreloadCount)
        self.adaptiveLookaheadSegments = Self.defaultPlaylistGrowthStepSegments
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
        guard !decision.hlsSignaling.codecs.isEmpty else {
            throw SyntheticHLSError.unsupportedCodecConfiguration(
                "Unsupported HEVC decoder configuration"
            )
        }
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
        adaptivePreloadCount = defaultPreloadCount
        adaptiveLookaheadSegments = Self.defaultPlaylistGrowthStepSegments
        do {
            _ = try await scheduler.segment(for: 0)
        } catch {
            streamInfo = nil
            initSegmentData = nil
            initSegmentInspection = nil
            packagingDecision = nil
            throw error
        }
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
        let selectedVideoTrack = info.tracks.first {
            $0.trackType == .video && $0.id == plan.videoTrack.id
        } ?? plan.videoTrack
        let resolution = "\(selectedVideoTrack.width ?? 1920)x\(selectedVideoTrack.height ?? 1080)"
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
            let baselineCount = max(Self.minimumPreloadSegments, preloadCount ?? adaptivePreloadCount)
            let growthStepSegments = max(Self.defaultPlaylistGrowthStepSegments, adaptiveLookaheadSegments)
            let desiredSegmentCount = max(baselineCount, sequences.count + growthStepSegments)
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

    public func promotePrefetch(preloadCount: Int, lookaheadSegments: Int) async {
        adaptivePreloadCount = max(adaptivePreloadCount, max(Self.minimumPreloadSegments, preloadCount))
        adaptiveLookaheadSegments = max(
            adaptiveLookaheadSegments,
            max(Self.defaultPlaylistGrowthStepSegments, lookaheadSegments)
        )

        let generated = await scheduler.generatedSequences()
        let baselineTargetSequence = max(0, adaptivePreloadCount - 1)
        let lookaheadTargetSequence = max(0, (generated.last ?? -1) + adaptiveLookaheadSegments)
        requestPrefetch(upTo: max(baselineTargetSequence, lookaheadTargetSequence))
        AppLog.nativeBridge.notice(
            "[NB-DIAG] hls.prefetch.promoted — preload=\(self.adaptivePreloadCount, privacy: .public) lookahead=\(self.adaptiveLookaheadSegments, privacy: .public) generated=\(generated.count, privacy: .public)"
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

    func generatedSequenceCountForTesting() async -> Int {
        await scheduler.generatedSequences().count
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
