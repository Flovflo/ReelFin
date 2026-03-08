import AVFoundation
import Foundation
import Shared

private struct VirtualOffsetIndex: Sendable {
    struct Entry: Sendable, Equatable {
        let byteOffset: Int64
        let timestampNs: Int64
    }

    private(set) var entries: [Entry] = []

    mutating func append(byteOffset: Int64, timestampNs: Int64) {
        if let last = entries.last, last.byteOffset == byteOffset {
            entries[entries.count - 1] = Entry(byteOffset: byteOffset, timestampNs: timestampNs)
            return
        }
        entries.append(Entry(byteOffset: byteOffset, timestampNs: timestampNs))
    }

    mutating func trim(atOrBefore byteOffset: Int64) {
        entries = entries.filter { $0.byteOffset <= byteOffset }
    }

    mutating func removeAll() {
        entries.removeAll()
    }

    func nearest(atOrBefore byteOffset: Int64) -> Entry? {
        entries.last(where: { $0.byteOffset <= byteOffset })
    }
}

private actor NativeBridgeCoreActor {
    private var streamByteOffset: Int64 = 0
    private var bufferedData = Data()
    private var cumulativeBytesGenerated: Int64 = 0
    private var offsetIndex = VirtualOffsetIndex()

    func bootstrap(initSegment: Data) {
        streamByteOffset = 0
        bufferedData = initSegment
        cumulativeBytesGenerated = Int64(initSegment.count)
        offsetIndex.removeAll()
    }

    func currentOffset() -> Int64 {
        streamByteOffset
    }

    func availableBytes() -> Int {
        bufferedData.count
    }

    func extract(length: Int) -> Data {
        guard length > 0 else { return Data() }
        let chunk = bufferedData.prefix(length)
        bufferedData.removeFirst(chunk.count)
        streamByteOffset += Int64(chunk.count)
        return chunk
    }

    func appendFragment(_ data: Data, firstTimestampNs: Int64) {
        offsetIndex.append(byteOffset: cumulativeBytesGenerated, timestampNs: firstTimestampNs)
        cumulativeBytesGenerated += Int64(data.count)
        bufferedData.append(data)
    }

    func nearestFragment(for byteOffset: Int64) -> VirtualOffsetIndex.Entry? {
        offsetIndex.nearest(atOrBefore: byteOffset)
    }

    func resetToInitSegment(_ initSegment: Data) {
        streamByteOffset = 0
        bufferedData = initSegment
        cumulativeBytesGenerated = Int64(initSegment.count)
        offsetIndex.removeAll()
    }

    func applyIndexedSeek(_ entry: VirtualOffsetIndex.Entry) {
        offsetIndex.trim(atOrBefore: entry.byteOffset)
        streamByteOffset = entry.byteOffset
        cumulativeBytesGenerated = entry.byteOffset
        bufferedData.removeAll()
    }

    func applyUnindexedSeek(_ byteOffset: Int64) {
        bufferedData.removeAll()
        streamByteOffset = byteOffset
    }

    func offsetIndexSnapshot() -> [VirtualOffsetIndex.Entry] {
        offsetIndex.entries
    }
}

/// Orchestrates the entire Native Bridge pipeline:
/// AVPlayer -> ResourceLoader -> NativeBridgeSession -> Repackager -> Demuxer -> HTTPRangeReader
public actor NativeBridgeSession: NativeBridgeResourceLoader.DataSource {
    private let plan: NativeBridgePlan
    private let reader: HTTPRangeReader
    private let demuxer: Demuxer
    private let repackager: Repackager
    private let core = NativeBridgeCoreActor()
    private let diagnostics: NativeBridgeDiagnosticsCollector

    private var streamInfo: StreamInfo?
    private var initSegment: Data?
    private var metrics = NativeBridgeMetrics()
    private let startDate = Date()

    public init(plan: NativeBridgePlan, token: String?) {
        self.plan = plan

        var headers: [String: String] = [:]
        if let token {
            headers["Authorization"] = "MediaBrowser Token=\"\(token)\""
            headers["X-Emby-Token"] = token
        }

        let config = HTTPRangeReader.Configuration.default
        self.reader = HTTPRangeReader(url: plan.sourceURL, headers: headers, config: config)
        self.demuxer = MatroskaDemuxer(reader: reader, plan: plan)

        let diagnosticsConfig = Self.resolveDiagnosticsConfig(plan: plan)
        self.diagnostics = NativeBridgeDiagnosticsCollector(config: diagnosticsConfig)
        self.repackager = FMP4Repackager(plan: plan, diagnostics: diagnostics)

        metrics.methodChosen = "Native Bridge"
        metrics.whyChosen = plan.whyChosen
        metrics.activeDiagnostics = diagnosticsConfig.enabled
    }

    public func prepare() async throws {
        let openStart = Date()
        AppLog.nativeBridge.notice("[NB-DIAG] prepare() starting demuxer.open()…")
        let info = try await demuxer.open()
        streamInfo = info
        let openMs = Date().timeIntervalSince(openStart) * 1000
        AppLog.nativeBridge.notice("[NB-DIAG] demuxer.open() completed in \(openMs, format: .fixed(precision: 1))ms — \(info.tracks.count) tracks, duration=\(info.durationNanoseconds)ns, seekable=\(info.seekable)")
        for t in info.tracks {
            AppLog.nativeBridge.notice("[NB-DIAG]   track id=\(t.id) type=\(t.trackType.rawValue, privacy: .public) codec=\(t.codecName, privacy: .public) \(t.width.map { "\($0)x\(t.height ?? 0)" } ?? "") cpSize=\(t.codecPrivate?.count ?? 0)")
        }

        AppLog.nativeBridge.notice("[NB-DIAG] generating init segment…")
        let initData = try await repackager.generateInitSegment(streamInfo: info)
        initSegment = initData
        await core.bootstrap(initSegment: initData)

        metrics.demuxInitMs = Date().timeIntervalSince(openStart) * 1000
        AppLog.nativeBridge.notice("[NB-DIAG] NativeBridgeSession prepared in \(self.metrics.demuxInitMs, format: .fixed(precision: 1))ms — init segment \(initData.count) bytes")
    }

    public nonisolated func makeAsset() -> AVURLAsset {
        let loader = NativeBridgeResourceLoader(dataSource: self)
        let asset = loader.makeAsset(for: plan.itemID)
        objc_setAssociatedObject(asset, &AssociatedKeys.loader, loader, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return asset
    }

    public func invalidate() {
        Task { await reader.invalidate() }
    }

    public func getMetrics() async -> NativeBridgeMetrics {
        var snapshot = metrics
        let rMetrics = await reader.metrics
        snapshot.cacheHitCount = rMetrics.cacheHitCount
        snapshot.cacheMissCount = rMetrics.cacheMissCount
        snapshot.rangeRequestCount = rMetrics.rangeRequestCount
        snapshot.retryCount = rMetrics.retryCount
        return snapshot
    }

    public func expectedStreamSize() async throws -> Int64 {
        50_000_000_000
    }

    public func beginResourceRequest(offset: Int64, length: Int) async -> UUID? {
        await diagnostics.recordRequestStart(offset: offset, length: length)
    }

    public func endResourceRequest(token: UUID?) async {
        await diagnostics.recordRequestFinish(token)
    }

    public func handleSeek(toByteOffset requestedOffset: Int64) async throws {
        let currentOffset = await core.currentOffset()
        guard requestedOffset != currentOffset else { return }

        let initSize = Int64(initSegment?.count ?? 0)
        if requestedOffset < initSize {
            await core.resetToInitSegment(initSegment ?? Data())
            _ = try await demuxer.seek(to: 0)
            metrics.seekCount += 1
            AppLog.playback.debug("NativeBridgeSession: Seek to beginning")
            return
        }

        if let nearest = await core.nearestFragment(for: requestedOffset) {
            AppLog.playback.debug(
                "NativeBridgeSession: Seek to byte \(requestedOffset) → fragment at \(nearest.byteOffset), ts=\(nearest.timestampNs)ns"
            )
            let actualTs = try await demuxer.seek(to: nearest.timestampNs)
            await core.applyIndexedSeek(nearest)
            metrics.seekCount += 1
            AppLog.playback.debug("NativeBridgeSession: Demuxer seeked to \(actualTs)ns")
            return
        }

        await core.applyUnindexedSeek(requestedOffset)
        metrics.seekCount += 1
        AppLog.playback.debug("NativeBridgeSession: Seek to \(requestedOffset) — no index entry, continuing from demuxer position")
    }

    public func readRepackagedData(offset: Int64, length: Int) async throws -> Data {
        let currentOffset = await core.currentOffset()
        if offset != currentOffset {
            try await handleSeek(toByteOffset: offset)
        }

        if await core.availableBytes() >= length {
            return await core.extract(length: length)
        }

        while await core.availableBytes() < length {
            var samples: [Sample] = []
            let targetSamples = metrics.totalFragmentsGenerated < 4 ? 12 : 36
            let demuxStart = Date()
            for _ in 0..<targetSamples {
                guard let sample = try await demuxer.readSample() else { break }
                samples.append(sample)
            }

            if samples.isEmpty {
                AppLog.nativeBridge.notice("[NB-DIAG] readRepackagedData: demuxer returned 0 samples (EOF?)")
                break
            }
            metrics.totalPacketsDemuxed += samples.count
            let demuxMs = Date().timeIntervalSince(demuxStart) * 1000

            let fragStart = Date()
            let fragment = try await repackager.generateFragment(samples: samples)
            let fragMs = Date().timeIntervalSince(fragStart) * 1000
            let firstPTS = samples.first?.ptsNanoseconds ?? 0
            await core.appendFragment(fragment, firstTimestampNs: firstPTS)
            metrics.totalFragmentsGenerated += 1

            if metrics.totalFragmentsGenerated <= 3 {
                let videoCount = samples.filter { $0.trackID == plan.videoTrack.id }.count
                let audioCount = samples.count - videoCount
                let firstVideoSize = samples.first(where: { $0.trackID == plan.videoTrack.id })?.data.count ?? 0
                AppLog.nativeBridge.notice("[NB-DIAG] fragment #\(self.metrics.totalFragmentsGenerated): \(samples.count) samples (v=\(videoCount) a=\(audioCount)), frag=\(fragment.count)B, firstPTS=\(firstPTS)ns, demux=\(demuxMs, format: .fixed(precision: 1))ms repack=\(fragMs, format: .fixed(precision: 1))ms, firstVideoAU=\(firstVideoSize)B")
            }

            if metrics.firstFragmentMs == 0 {
                metrics.firstFragmentMs = Date().timeIntervalSince(startDate) * 1000
                AppLog.nativeBridge.notice("[NB-DIAG] first fragment at \(self.metrics.firstFragmentMs, format: .fixed(precision: 1))ms from session start")
            }
        }

        let extractLen = min(length, await core.availableBytes())
        return await core.extract(length: extractLen)
    }

    public func exportDebugBundle(exporter: NativeBridgeDebugBundleExporter = FileNativeBridgeDebugBundleExporter()) async throws -> URL? {
        guard let info = streamInfo else { return nil }
        let index = await core.offsetIndexSnapshot()
        var trackLines = [
            "tracks=\(info.tracks.count)",
            "duration_ns=\(info.durationNanoseconds)",
            "seekable=\(info.seekable)",
            "offset_index_entries=\(index.count)"
        ]
        trackLines.append(contentsOf: info.tracks.map {
            "track id=\($0.id) type=\($0.trackType.rawValue) codec=\($0.codecName) range=\($0.transferCharacteristic ?? -1)/\($0.colourPrimaries ?? -1)"
        })
        guard let bundle = await diagnostics.snapshot(itemID: plan.itemID, trackDump: trackLines.joined(separator: "\n")) else {
            return nil
        }
        return try exporter.export(bundle: bundle)
    }

    private static func resolveDiagnosticsConfig(plan: NativeBridgePlan) -> NativeBridgeDiagnosticsConfig {
        if plan.diagnostics.enabled {
            return plan.diagnostics
        }
        let env = ProcessInfo.processInfo.environment
        let enabled = (env["REELFIN_NATIVE_BRIDGE_DIAGNOSTICS"] == "1")
        if !enabled {
            return .disabled
        }
        return NativeBridgeDiagnosticsConfig(enabled: true, dumpSegments: true, maxFragmentDumpCount: 8)
    }
}

private struct AssociatedKeys {
    static var loader = "NativeBridgeResourceLoaderKey"
}
