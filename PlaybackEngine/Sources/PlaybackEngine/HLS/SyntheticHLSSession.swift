import Foundation
import CoreMedia
import Shared

public enum SyntheticHLSError: Error, LocalizedError {
    case notPrepared
    case endOfStream
    case missingSegment(Int)
    case unsupportedCodecConfiguration(String)
    case independentBoundaryUnavailable(sequence: Int, samplesScanned: Int)
    case segmentExceedsWorkingSet(sequence: Int, bytes: Int, limit: Int)
    case workingSetCapacityExhausted(sequence: Int)
    case generationInProgress(sequence: Int)

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
        case .segmentExceedsWorkingSet(let sequence, let bytes, let limit):
            return "Segment \(sequence) uses \(bytes) bytes and exceeds the \(limit)-byte HLS working set"
        case .workingSetCapacityExhausted(let sequence):
            return "Segment \(sequence) cannot enter the HLS working set while the published snapshot is pinned"
        case .generationInProgress(let sequence):
            return "Segment \(sequence) cannot start while another HLS generation is in progress"
        }
    }
}

public struct SyntheticHLSSegment: Sendable {
    public let sequence: Int
    public let data: Data
    public let duration: Double
    public let isAdvertised: Bool
}

enum PlaylistOperationTransition: Sendable, Equatable {
    case acquired
    case queued
}

public actor SegmentCacheActor {
    private let maxBytes: Int
    private let maxSegments: Int
    private var storage: [Int: SyntheticHLSSegment] = [:]
    private var order: [Int] = []
    private var currentBytes: Int = 0
    private var generation: Int = 0
    private var lastPublishedSequence: Int?
    private var beforeAdvertisedEntryHookForTesting: (@Sendable () async -> Void)?

    public init(maxBytes: Int = 16 * 1024 * 1024, maxSegments: Int = 12) {
        self.maxBytes = max(1, maxBytes)
        self.maxSegments = max(1, maxSegments)
    }

    public func put(
        _ data: Data,
        duration: Double,
        for sequence: Int,
        expectedGeneration: Int? = nil
    ) throws {
        if let expectedGeneration, expectedGeneration != generation {
            throw CancellationError()
        }
        guard data.count <= maxBytes else {
            throw SyntheticHLSError.segmentExceedsWorkingSet(
                sequence: sequence,
                bytes: data.count,
                limit: maxBytes
            )
        }
        if let old = storage[sequence] {
            currentBytes -= old.data.count
        }
        let previousStorage = storage
        let previousOrder = order
        let previousBytes = currentBytes
        storage[sequence] = SyntheticHLSSegment(
            sequence: sequence,
            data: data,
            duration: duration,
            isAdvertised: false
        )
        touch(sequence)
        currentBytes += data.count
        evictIfNeeded(protecting: sequence)
        guard currentBytes <= maxBytes, storage.count <= maxSegments else {
            storage = previousStorage
            order = previousOrder
            currentBytes = previousBytes + (previousStorage[sequence]?.data.count ?? 0)
            throw SyntheticHLSError.workingSetCapacityExhausted(sequence: sequence)
        }
    }

    public func retainedEntries() -> [SyntheticHLSSegment] {
        storage.values.sorted { $0.sequence < $1.sequence }
    }

    public func advertiseRetained(limit: Int? = nil) -> [SyntheticHLSSegment] {
        let retained = storage.keys.sorted()
        let selected = Array(retained.prefix(max(0, limit ?? retained.count)))
        let selectedSet = Set(selected)
        for sequence in retained {
            guard let entry = storage[sequence] else { continue }
            storage[sequence] = SyntheticHLSSegment(
                sequence: entry.sequence,
                data: entry.data,
                duration: entry.duration,
                isAdvertised: selectedSet.contains(sequence)
            )
        }
        advancePublishedFrontier(with: selected)
        return selected.compactMap { storage[$0] }
    }

    public func publishRetainedWindow(
        startupLimit: Int? = nil,
        includeReserve: Bool = false
    ) -> [SyntheticHLSSegment] {
        commitPublishedWindow(
            publishedWindowCandidate(
                startupLimit: startupLimit,
                includeReserve: includeReserve
            )
        )
    }

    func publishedWindowCandidate(
        startupLimit: Int? = nil,
        includeReserve: Bool = false
    ) -> [Int] {
        let retained = storage.keys.sorted()
        let selected: [Int]
        if let startupLimit {
            selected = Array(retained.prefix(max(0, startupLimit)))
        } else if includeReserve {
            selected = retained
        } else {
            let currentPublished = retained.filter { storage[$0]?.isAdvertised == true }
            let nextRequired = lastPublishedSequence.map { $0 == Int.max ? Int.max : $0 + 1 }
                ?? retained.first
            let future = retained.filter { sequence in
                guard let nextRequired else { return false }
                return sequence >= nextRequired
            }
            if let nextRequired, future.first == nextRequired {
                var newWindow: [Int] = []
                var windowBytes = 0
                var expectedSequence = nextRequired
                for sequence in future {
                    guard sequence == expectedSequence,
                          let entry = storage[sequence] else { break }
                    if !newWindow.isEmpty {
                        guard newWindow.count < maxSegments,
                              entry.data.count <= maxBytes,
                              windowBytes <= maxBytes - entry.data.count else { break }
                    }
                    newWindow.append(sequence)
                    windowBytes += entry.data.count
                    if expectedSequence == Int.max { break }
                    expectedSequence += 1
                }

                for sequence in currentPublished.reversed() {
                    guard let first = newWindow.first,
                          first > Int.min,
                          sequence == first - 1,
                          let entry = storage[sequence],
                          newWindow.count < maxSegments,
                          entry.data.count <= maxBytes,
                          windowBytes <= maxBytes - entry.data.count else { break }
                    newWindow.insert(sequence, at: 0)
                    windowBytes += entry.data.count
                }
                selected = newWindow
            } else if !currentPublished.isEmpty {
                // A full published window cannot accept an unknown-size successor.
                // At this snapshot boundary only, release the oldest already-published
                // entries so one sequential insertion can be staged without ever
                // skipping an unpublished sequence.
                let countLimit = max(1, maxSegments - 1)
                let reserveBytes = storage.values.lazy.map { $0.data.count }.max() ?? 0
                let publishedByteLimit = max(0, maxBytes - reserveBytes)
                let currentPublishedBytes = currentPublished.reduce(0) {
                    $0 + (storage[$1]?.data.count ?? 0)
                }
                if currentPublished.count <= countLimit,
                   currentPublishedBytes <= publishedByteLimit {
                    selected = currentPublished
                } else {
                    var selectedReversed: [Int] = []
                    var selectedBytes = 0
                    for sequence in currentPublished.reversed() {
                        guard let entry = storage[sequence] else { continue }
                        if selectedReversed.isEmpty {
                            selectedReversed.append(sequence)
                            selectedBytes = entry.data.count
                            continue
                        }
                        guard selectedReversed.count < countLimit,
                              entry.data.count <= publishedByteLimit,
                              selectedBytes <= publishedByteLimit - entry.data.count else { break }
                        selectedReversed.append(sequence)
                        selectedBytes += entry.data.count
                    }
                    selected = Array(selectedReversed.reversed())
                }
            } else {
                selected = Array(retained.prefix(1))
            }
        }
        return selected
    }

    func commitPublishedWindow(_ selected: [Int]) -> [SyntheticHLSSegment] {
        let retained = storage.keys.sorted()
        let selectedSet = Set(selected)
        for sequence in retained {
            guard let entry = storage[sequence] else { continue }
            storage[sequence] = SyntheticHLSSegment(
                sequence: entry.sequence,
                data: entry.data,
                duration: entry.duration,
                isAdvertised: selectedSet.contains(sequence)
            )
        }
        advancePublishedFrontier(with: selected)
        return selected.compactMap { storage[$0] }
    }

    public func advertisedEntry(for sequence: Int) async -> SyntheticHLSSegment? {
        if let beforeAdvertisedEntryHookForTesting {
            await beforeAdvertisedEntryHookForTesting()
        }
        guard let entry = storage[sequence], entry.isAdvertised else { return nil }
        return entry
    }

    func setBeforeAdvertisedEntryHookForTesting(
        _ hook: (@Sendable () async -> Void)?
    ) {
        beforeAdvertisedEntryHookForTesting = hook
    }

    public func segmentCapacity() -> Int { maxSegments }

    public func availablePrefetchSlots() -> Int {
        availablePrefetchSlots(
            advertisedSequences: Set(storage.values.filter(\.isAdvertised).map(\.sequence)),
            publishedFrontier: lastPublishedSequence
        )
    }

    func availablePrefetchSlots(publishing sequences: [Int]) -> Int {
        let newest = sequences.max()
        let publishedFrontier = [lastPublishedSequence, newest].compactMap { $0 }.max()
        return availablePrefetchSlots(
            advertisedSequences: Set(sequences),
            publishedFrontier: publishedFrontier
        )
    }

    private func availablePrefetchSlots(
        advertisedSequences: Set<Int>,
        publishedFrontier: Int?
    ) -> Int {
        guard let publishedFloor = advertisedSequences.min() else { return 0 }
        if let publishedFrontier,
           storage.values.contains(where: {
               !advertisedSequences.contains($0.sequence)
                   && $0.sequence > publishedFrontier
           }) {
            return 0
        }
        let reclaimable = storage.values.filter {
            !advertisedSequences.contains($0.sequence) && $0.sequence < publishedFloor
        }
        let protectedBytes = currentBytes - reclaimable.reduce(0) { $0 + $1.data.count }
        let protectedCount = storage.count - reclaimable.count
        let countSlots = max(0, maxSegments - protectedCount)
        let nextInsertionReserve = storage.values.lazy.map { $0.data.count }.max() ?? maxBytes
        let hasByteReserve = nextInsertionReserve <= maxBytes
            && protectedBytes <= maxBytes - nextInsertionReserve
        return countSlots > 0 && hasByteReserve ? 1 : 0
    }

    func availableInitialPrefetchSlots() -> Int {
        guard !storage.isEmpty,
              !storage.values.contains(where: \.isAdvertised),
              storage.count < maxSegments else { return 0 }
        let nextInsertionReserve = storage.values.lazy.map { $0.data.count }.max() ?? maxBytes
        guard nextInsertionReserve <= maxBytes,
              currentBytes <= maxBytes - nextInsertionReserve else { return 0 }
        return 1
    }

    @discardableResult
    public func invalidateForSeek(targetPTS: Int64) -> Int {
        _ = targetPTS
        generation += 1
        storage.removeAll()
        order.removeAll()
        currentBytes = 0
        lastPublishedSequence = nil
        return generation
    }

    private func touch(_ sequence: Int) {
        order.removeAll(where: { $0 == sequence })
        order.append(sequence)
    }

    private func advancePublishedFrontier(with sequences: [Int]) {
        guard let newest = sequences.max() else { return }
        lastPublishedSequence = max(lastPublishedSequence ?? newest, newest)
    }

    private func evictIfNeeded(protecting insertedSequence: Int) {
        while currentBytes > maxBytes || storage.count > maxSegments {
            guard let publishedFloor = storage.values.lazy
                .filter(\.isAdvertised)
                .map(\.sequence)
                .min() else { return }
            guard let evictionIndex = order.firstIndex(where: { sequence in
                sequence != insertedSequence
                    && sequence < publishedFloor
                    && storage[sequence]?.isAdvertised == false
            }) else { return }
            let evicted = order.remove(at: evictionIndex)
            if let removed = storage.removeValue(forKey: evicted) {
                currentBytes -= removed.data.count
            }
        }
    }
}

public struct GeneratedHLSSegment: Sendable {
    public let sequence: Int
    public let data: Data
    public let duration: Double
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
    private var pendingBoundarySample: Sample?
    private var generation: Int = 0
    private var activeGeneration: (sequence: Int, generation: Int)?

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

    public func segment(for sequence: Int) async throws -> GeneratedHLSSegment {
        guard sequence == nextSequenceToGenerate else {
            throw SyntheticHLSError.missingSegment(sequence)
        }
        guard activeGeneration == nil else {
            throw SyntheticHLSError.generationInProgress(sequence: sequence)
        }
        let expectedGeneration = generation
        activeGeneration = (sequence, expectedGeneration)
        defer {
            if activeGeneration?.sequence == sequence,
               activeGeneration?.generation == expectedGeneration {
                activeGeneration = nil
            }
        }
        try validateGeneration(expectedGeneration)
        let samples = try await collectSegmentSamples(
            sequence: sequence,
            expectedGeneration: expectedGeneration
        )
        guard !samples.isEmpty else {
            throw SyntheticHLSError.endOfStream
        }
        let fragment = try await repackager.generateFragment(samples: samples)
        try validateGeneration(expectedGeneration)
        guard generation == expectedGeneration,
              sequence == nextSequenceToGenerate else {
            throw CancellationError()
        }
        let durationNs = samples.reduce(Int64(0)) {
            Self.saturatedAdd($0, max(0, $1.durationNanoseconds))
        }
        let durationSeconds = max(0.001, Double(durationNs) / 1_000_000_000.0)
        if sequence == 0 {
            AppLog.nativeBridge.notice(
                "[NB-DIAG] hls.startup.segment-built — samples=\(samples.count, privacy: .public) duration=\(durationSeconds, format: .fixed(precision: 3))s bytes=\(fragment.count, privacy: .public)"
            )
        }
        nextSequenceToGenerate += 1
        return GeneratedHLSSegment(
            sequence: sequence,
            data: fragment,
            duration: durationSeconds
        )
    }

    public func generatedSequences() -> [Int] {
        Array(0..<nextSequenceToGenerate)
    }

    public func nextSequence() -> Int { nextSequenceToGenerate }

    public func invalidateAfterSeek() {
        generation += 1
        nextSequenceToGenerate = 0
        pendingBoundarySample = nil
    }

    private func collectSegmentSamples(
        sequence: Int,
        expectedGeneration: Int
    ) async throws -> [Sample] {
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

        try validateGeneration(expectedGeneration)
        if let pendingBoundarySample {
            samples.append(pendingBoundarySample)
            durationNs = Self.saturatedAdd(durationNs, max(0, pendingBoundarySample.durationNanoseconds))
            sawVideoSample = pendingBoundarySample.trackID == videoTrackID
            sawAudioSample = pendingBoundarySample.trackID == audioTrackID
            scannedSamples = 1
            scannedBytes = pendingBoundarySample.data.count
            scannedDurationNs = max(0, pendingBoundarySample.durationNanoseconds)
            try validateGeneration(expectedGeneration)
            self.pendingBoundarySample = nil
        }

        while true {
            try validateGeneration(expectedGeneration)
            guard let sample = try await demuxer.readSample() else { break }
            try validateGeneration(expectedGeneration)
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
                try validateGeneration(expectedGeneration)
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

        try validateGeneration(expectedGeneration)
        return samples
    }

    private func validateGeneration(_ expectedGeneration: Int) throws {
        try Task.checkCancellation()
        guard generation == expectedGeneration else { throw CancellationError() }
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
    private var prefetchTask: Task<Void, Never>?
    private var prefetchTaskGeneration: Int?
    private var prefetchTargetSequence = 0
    private var adaptivePreloadCount: Int
    private var adaptiveLookaheadSegments: Int
    private var workGeneration = 0
    private var cacheGeneration = 0
    private var terminalWorkingSetError: SyntheticHLSError?
    private var beforeCacheCommitHookForTesting: (@Sendable (Int) async -> Void)?
    private var playlistOperationTransitionHookForTesting: (
        @Sendable (PlaylistOperationTransition) async -> Void
    )?
    private var beforePlaylistCommitHookForTesting: (@Sendable () async -> Void)?
    private var duringPlaylistCommitHookForTesting: (@Sendable () async -> Void)?
    private var nextPlaylistOperationToken = 0
    private var playlistOperationOwner: Int?
    private var playlistOperationWaiters: [CheckedContinuation<Void, Never>] = []
    private var playlistPublicationOwner: Int?
    private var activeAdvertisedSegmentReaders = 0
    private var advertisedSegmentWaiters: [CheckedContinuation<Void, Never>] = []
    private var advertisedSegmentDrainWaiters: [CheckedContinuation<Void, Never>] = []
    private let playlistTargetDurationSeconds = 12

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
        let operationToken = await acquirePlaylistOperation()
        defer { releasePlaylistOperation(operationToken) }
        workGeneration += 1
        await cancelPrefetchAndWait()
        cacheGeneration = await cache.invalidateForSeek(targetPTS: 0)
        await scheduler.invalidateAfterSeek()
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
        prefetchTask = nil
        prefetchTaskGeneration = nil
        prefetchTargetSequence = 0
        adaptivePreloadCount = defaultPreloadCount
        adaptiveLookaheadSegments = Self.defaultPlaylistGrowthStepSegments
        terminalWorkingSetError = nil
        do {
            _ = try await generateNextSegment(expectedSequence: 0)
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
        try await advertisedSegment(sequence: sequence)
    }

    public func advertisedSegment(sequence: Int) async throws -> Data {
        await acquireAdvertisedSegmentRead()
        defer { releaseAdvertisedSegmentRead() }
        guard let entry = await cache.advertisedEntry(for: sequence) else {
            throw SyntheticHLSError.missingSegment(sequence)
        }
        return entry.data
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
        let operationToken = await acquirePlaylistOperation()
        defer { releasePlaylistOperation(operationToken) }
        guard streamInfo != nil else {
            throw SyntheticHLSError.notPrepared
        }
        if let terminalWorkingSetError {
            throw terminalWorkingSetError
        }

        var retained = await cache.retainedEntries()
        if retained.isEmpty {
            do {
                let next = await scheduler.nextSequence()
                _ = try await generateNextSegment(expectedSequence: next)
                retained = await cache.retainedEntries()
            } catch SyntheticHLSError.endOfStream {
                reachedEndOfStream = true
            }
        }

        var candidateSequences = await cache.publishedWindowCandidate(
            startupLimit: startupPreflightSnapshot ? 1 : nil,
            includeReserve: reachedEndOfStream
        )

        var nextPrefetchTarget: Int?
        if !reachedEndOfStream, !startupPreflightSnapshot {
            let capacity = await cache.segmentCapacity()
            let baselineCount = min(
                capacity,
                max(Self.minimumPreloadSegments, preloadCount ?? adaptivePreloadCount)
            )
            let growthStepSegments = min(
                capacity,
                max(Self.defaultPlaylistGrowthStepSegments, adaptiveLookaheadSegments)
            )
            let publishedAvailableSlots = await cache.availablePrefetchSlots()
            let availableSlots = publishedAvailableSlots > 0
                ? publishedAvailableSlots
                : await cache.availableInitialPrefetchSlots()
            let requestedAdditional = availableSlots > 0
                ? min(
                    availableSlots,
                    max(max(0, baselineCount - candidateSequences.count), growthStepSegments)
                )
                : 0
            if requestedAdditional > 0 {
                let next = await scheduler.nextSequence()
                nextPrefetchTarget = next + requestedAdditional - 1
            }
        }

        if let nextPrefetchTarget {
            requestPrefetch(upTo: nextPrefetchTarget)
            if candidateSequences.count < Self.minimumPreloadSegments {
                let task = prefetchTask
                await task?.value
                if let terminalWorkingSetError {
                    throw terminalWorkingSetError
                }
                candidateSequences = await cache.publishedWindowCandidate(
                    includeReserve: reachedEndOfStream
                )
            }
        }
        var postCommitPrefetchTarget: Int?
        if nextPrefetchTarget == nil,
           !reachedEndOfStream,
           !startupPreflightSnapshot,
           await cache.availablePrefetchSlots(publishing: candidateSequences) > 0 {
            postCommitPrefetchTarget = await scheduler.nextSequence()
        }
        if let beforePlaylistCommitHookForTesting {
            await beforePlaylistCommitHookForTesting()
        }
        await acquirePlaylistPublication(operationToken)
        if let duringPlaylistCommitHookForTesting {
            await duringPlaylistCommitHookForTesting()
        }
        retained = await cache.commitPublishedWindow(candidateSequences)
        releasePlaylistPublication(operationToken)
        if let postCommitPrefetchTarget {
            requestPrefetch(upTo: postCommitPrefetchTarget)
        }
        let segments = retained.map { entry in
            HLSMediaPlaylistSegment(
                uri: absoluteURI(path: "segment_\(entry.sequence).m4s", relativeTo: baseURL),
                duration: entry.duration
            )
        }

        return manifestBuilder.makeMediaPlaylist(
            targetDuration: playlistTargetDurationSeconds,
            mediaSequence: retained.first?.sequence ?? 0,
            initSegmentURI: absoluteURI(path: "init.mp4", relativeTo: baseURL),
            segments: segments,
            endList: startupPreflightSnapshot || reachedEndOfStream
        )
    }

    public func promotePrefetch(preloadCount: Int, lookaheadSegments: Int) async {
        let capacity = await cache.segmentCapacity()
        adaptivePreloadCount = min(
            capacity,
            max(adaptivePreloadCount, max(Self.minimumPreloadSegments, preloadCount))
        )
        adaptiveLookaheadSegments = max(
            adaptiveLookaheadSegments,
            max(Self.defaultPlaylistGrowthStepSegments, lookaheadSegments)
        )
        adaptiveLookaheadSegments = min(capacity, adaptiveLookaheadSegments)

        let retained = await cache.retainedEntries()
        let availableSlots = await cache.availablePrefetchSlots()
        let desiredAdditional = min(
            availableSlots,
            max(max(0, adaptivePreloadCount - retained.count), adaptiveLookaheadSegments)
        )
        if desiredAdditional > 0 {
            let next = await scheduler.nextSequence()
            requestPrefetch(upTo: next + desiredAdditional - 1)
        }
        AppLog.nativeBridge.notice(
            "[NB-DIAG] hls.prefetch.promoted — preload=\(self.adaptivePreloadCount, privacy: .public) lookahead=\(self.adaptiveLookaheadSegments, privacy: .public) retained=\(retained.count, privacy: .public)"
        )
    }

    public func invalidateForSeek(targetPTS: Int64) async throws {
        let operationToken = await acquirePlaylistOperation()
        defer { releasePlaylistOperation(operationToken) }
        workGeneration += 1
        await cancelPrefetchAndWait()
        _ = try await demuxer.seek(to: targetPTS)
        cacheGeneration = await cache.invalidateForSeek(targetPTS: targetPTS)
        await scheduler.invalidateAfterSeek()
        reachedEndOfStream = false
        prefetchTask = nil
        prefetchTaskGeneration = nil
        prefetchTargetSequence = 0
        terminalWorkingSetError = nil
    }

    func generatedSequenceCountForTesting() async -> Int {
        await cache.retainedEntries().count
    }

    func setBeforeCacheCommitHookForTesting(
        _ hook: (@Sendable (Int) async -> Void)?
    ) {
        beforeCacheCommitHookForTesting = hook
    }

    func waitForPrefetchForTesting() async {
        let task = prefetchTask
        await task?.value
    }

    func setBeforePlaylistCommitHookForTesting(
        _ hook: (@Sendable () async -> Void)?
    ) {
        beforePlaylistCommitHookForTesting = hook
    }

    func setPlaylistOperationTransitionHookForTesting(
        _ hook: (@Sendable (PlaylistOperationTransition) async -> Void)?
    ) {
        playlistOperationTransitionHookForTesting = hook
    }

    func setDuringPlaylistCommitHookForTesting(
        _ hook: (@Sendable () async -> Void)?
    ) {
        duringPlaylistCommitHookForTesting = hook
    }

    func playlistOperationWaiterCountForTesting() -> Int {
        playlistOperationWaiters.count
    }

    func advertisedSegmentWaiterCountForTesting() -> Int {
        advertisedSegmentWaiters.count
    }

    func waitForPlaylistOperationWaiterCountForTesting(_ expectedCount: Int) async {
        while playlistOperationWaiters.count < expectedCount {
            await Task.yield()
        }
    }

    func waitForAdvertisedSegmentWaiterCountForTesting(_ expectedCount: Int) async {
        while advertisedSegmentWaiters.count < expectedCount {
            await Task.yield()
        }
    }

    func waitForPlaylistPublicationForTesting() async {
        while playlistPublicationOwner == nil {
            await Task.yield()
        }
    }

    private func acquirePlaylistOperation() async -> Int {
        while playlistOperationOwner != nil {
            if let playlistOperationTransitionHookForTesting {
                await playlistOperationTransitionHookForTesting(.queued)
            }
            await withCheckedContinuation { continuation in
                playlistOperationWaiters.append(continuation)
            }
        }
        nextPlaylistOperationToken = nextPlaylistOperationToken == Int.max
            ? 1
            : nextPlaylistOperationToken + 1
        let token = nextPlaylistOperationToken
        playlistOperationOwner = token
        if let playlistOperationTransitionHookForTesting {
            await playlistOperationTransitionHookForTesting(.acquired)
        }
        return token
    }

    private func releasePlaylistOperation(_ token: Int) {
        guard playlistOperationOwner == token else { return }
        playlistOperationOwner = nil
        let waiters = playlistOperationWaiters
        playlistOperationWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func acquirePlaylistPublication(_ token: Int) async {
        precondition(playlistOperationOwner == token)
        precondition(playlistPublicationOwner == nil)
        playlistPublicationOwner = token
        if activeAdvertisedSegmentReaders > 0 {
            await withCheckedContinuation { continuation in
                advertisedSegmentDrainWaiters.append(continuation)
            }
        }
        precondition(playlistPublicationOwner == token)
        precondition(activeAdvertisedSegmentReaders == 0)
    }

    private func releasePlaylistPublication(_ token: Int) {
        guard playlistPublicationOwner == token else { return }
        playlistPublicationOwner = nil
        let waiters = advertisedSegmentWaiters
        advertisedSegmentWaiters.removeAll()
        activeAdvertisedSegmentReaders += waiters.count
        waiters.forEach { $0.resume() }
    }

    private func acquireAdvertisedSegmentRead() async {
        if playlistPublicationOwner != nil {
            await withCheckedContinuation { continuation in
                advertisedSegmentWaiters.append(continuation)
            }
            return
        }
        activeAdvertisedSegmentReaders += 1
    }

    private func releaseAdvertisedSegmentRead() {
        precondition(activeAdvertisedSegmentReaders > 0)
        activeAdvertisedSegmentReaders -= 1
        guard activeAdvertisedSegmentReaders == 0 else { return }
        let waiters = advertisedSegmentDrainWaiters
        advertisedSegmentDrainWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func requestPrefetch(upTo sequence: Int) {
        guard !reachedEndOfStream else { return }
        guard prefetchTask == nil else { return }
        prefetchTargetSequence = sequence

        let generation = workGeneration
        let session = self
        prefetchTaskGeneration = generation
        prefetchTask = Task(priority: .utility) {
            await session.runPrefetchLoop(generation: generation)
        }
    }

    private func runPrefetchLoop(generation: Int) async {
        defer { finishPrefetch(generation: generation) }
        while true {
            guard !Task.isCancelled, generation == workGeneration else { return }
            if reachedEndOfStream {
                return
            }

            let next = await scheduler.nextSequence()
            let target = prefetchTargetSequence
            if next > target {
                return
            }

            do {
                _ = try await generateNextSegment(expectedSequence: next)
            } catch SyntheticHLSError.endOfStream {
                guard generation == workGeneration else { return }
                reachedEndOfStream = true
                return
            } catch let error as SyntheticHLSError {
                guard generation == workGeneration else { return }
                if case .segmentExceedsWorkingSet = error {
                    terminalWorkingSetError = error
                } else if case .workingSetCapacityExhausted = error {
                    terminalWorkingSetError = error
                }
                AppLog.nativeBridge.warning(
                    "[NB-DIAG] hls.prefetch.failed — sequence=\(next, privacy: .public) reason=\(error.localizedDescription, privacy: .public)"
                )
                return
            } catch {
                if error is CancellationError || Task.isCancelled { return }
                guard generation == workGeneration else { return }
                AppLog.nativeBridge.warning(
                    "[NB-DIAG] hls.prefetch.failed — sequence=\(next, privacy: .public) reason=\(error.localizedDescription, privacy: .public)"
                )
                return
            }
        }
    }

    private func finishPrefetch(generation: Int) {
        guard prefetchTaskGeneration == generation else { return }
        prefetchTask = nil
        prefetchTaskGeneration = nil
    }

    private func cancelPrefetchAndWait() async {
        let task = prefetchTask
        prefetchTask = nil
        prefetchTaskGeneration = nil
        task?.cancel()
        await task?.value
    }

    private func generateNextSegment(expectedSequence: Int) async throws -> SyntheticHLSSegment {
        let generation = workGeneration
        let expectedCacheGeneration = cacheGeneration
        let generated = try await scheduler.segment(for: expectedSequence)
        if let beforeCacheCommitHookForTesting {
            await beforeCacheCommitHookForTesting(generated.sequence)
        }
        guard generation == workGeneration else { throw CancellationError() }
        try await cache.put(
            generated.data,
            duration: generated.duration,
            for: generated.sequence,
            expectedGeneration: expectedCacheGeneration
        )
        return SyntheticHLSSegment(
            sequence: generated.sequence,
            data: generated.data,
            duration: generated.duration,
            isAdvertised: false
        )
    }

    private func absoluteURI(path: String, relativeTo baseURL: URL?) -> String {
        guard let baseURL else { return path }
        return baseURL.appendingPathComponent(path).absoluteString
    }
}
