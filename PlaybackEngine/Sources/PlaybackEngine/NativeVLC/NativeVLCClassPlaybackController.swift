import Foundation
import NativeMediaCore
import Shared

public struct NativeVLCPlaybackSnapshot: Sendable, Equatable {
    public var overlayLines: [String]
    public var routeDescription: String
    public var playbackURL: URL?
    public var playbackHeaders: [String: String]
    public var startTimeSeconds: Double?
    public var playbackErrorMessage: String?
    public var audioTracks: [Shared.MediaTrack]
    public var subtitleTracks: [Shared.MediaTrack]
    public var selectedAudioTrackID: String?
    public var selectedSubtitleTrackID: String?

    public init(
        overlayLines: [String],
        routeDescription: String,
        playbackURL: URL? = nil,
        playbackHeaders: [String: String] = [:],
        startTimeSeconds: Double? = nil,
        playbackErrorMessage: String? = nil,
        audioTracks: [Shared.MediaTrack] = [],
        subtitleTracks: [Shared.MediaTrack] = [],
        selectedAudioTrackID: String? = nil,
        selectedSubtitleTrackID: String? = nil
    ) {
        self.overlayLines = overlayLines
        self.routeDescription = routeDescription
        self.playbackURL = playbackURL
        self.playbackHeaders = playbackHeaders
        self.startTimeSeconds = startTimeSeconds
        self.playbackErrorMessage = playbackErrorMessage
        self.audioTracks = audioTracks
        self.subtitleTracks = subtitleTracks
        self.selectedAudioTrackID = selectedAudioTrackID
        self.selectedSubtitleTrackID = selectedSubtitleTrackID
    }
}

public actor NativeVLCClassPlaybackController {
    private let apiClient: any JellyfinAPIClientProtocol & Sendable
    private let resolver: OriginalMediaResolver
    private let probeService = ContainerProbeService()
    private var stateMachine = NativePlaybackStateMachine()

    public init(
        apiClient: any JellyfinAPIClientProtocol & Sendable,
        resolver: OriginalMediaResolver = OriginalMediaResolver()
    ) {
        self.apiClient = apiClient
        self.resolver = resolver
    }

    public func prepare(
        itemID: String,
        configuration: ServerConfiguration,
        session: UserSession,
        nativeConfig: NativeVLCClassPlayerConfig,
        startTimeTicks: Int64?
    ) async throws -> NativeVLCPlaybackSnapshot {
        AppLog.playback.notice("nativevlc.original.resolve.start — item=\(AppLogFormat.shortIdentifier(itemID), privacy: .public)")
        stateMachine.apply(.beginResolve)
        let options = PlaybackInfoOptions(
            mode: .performance,
            enableDirectPlay: true,
            enableDirectStream: false,
            allowTranscoding: nativeConfig.allowServerTranscodeFallback,
            maxStreamingBitrate: nil,
            startTimeTicks: startTimeTicks,
            allowVideoStreamCopy: true,
            allowAudioStreamCopy: true,
            deviceProfile: nil
        )
        let sources = try await apiClient.fetchPlaybackSources(itemID: itemID, options: options)
        let resolution = try resolver.resolve(
            request: OriginalMediaRequest(itemID: itemID, startTimeTicks: startTimeTicks),
            sources: sources,
            configuration: configuration,
            session: session,
            nativeConfig: nativeConfig
        )
        if let violation = NativeVLCClassRouteGuard.validateOriginalPlaybackURL(resolution.url).first {
            throw violation
        }
        AppLog.playback.notice(
            "nativevlc.original.resolve.ok — item=\(AppLogFormat.shortIdentifier(itemID), privacy: .public) source=\(resolution.mediaSource.id, privacy: .public) selectedPath=\(resolution.selectedPath, privacy: .public)"
        )
        stateMachine.apply(.originalResolved)
        return try await prepareResolved(
            resolution,
            nativeConfig: nativeConfig,
            startTimeTicks: startTimeTicks
        )
    }

    private func prepareResolved(
        _ resolution: OriginalMediaResolution,
        nativeConfig: NativeVLCClassPlayerConfig,
        startTimeTicks: Int64?
    ) async throws -> NativeVLCPlaybackSnapshot {
        let source = HTTPRangeByteSource(url: resolution.url, headers: resolution.headers)
        AppLog.playback.notice(
            "nativevlc.byteSource.open — source=\(resolution.mediaSource.id, privacy: .public) type=HTTPRangeByteSource"
        )
        stateMachine.apply(.probeStarted)
        AppLog.playback.notice("nativevlc.probe.start — source=\(resolution.mediaSource.id, privacy: .public)")
        let probe = try await probeService.probe(source: source, hint: resolution.mediaSource.container)
        AppLog.playback.notice(
            "nativevlc.probe.result — source=\(resolution.mediaSource.id, privacy: .public) format=\(probe.format.rawValue, privacy: .public) confidence=\(probe.confidence.rawValue, privacy: .public)"
        )
        let metrics = await source.metrics()
        let demuxer: any MediaDemuxer
        let stream: DemuxerStreamInfo
        do {
            stateMachine.apply(.demuxStarted)
            demuxer = try DemuxerFactory(
                allowCustomDemuxers: nativeConfig.allowCustomDemuxers,
                enableExperimentalMKV: nativeConfig.enableExperimentalMKV
            ).makeDemuxer(format: probe.format, source: source, sourceURL: resolution.url)
            AppLog.playback.notice(
                "nativevlc.demuxer.selected — source=\(resolution.mediaSource.id, privacy: .public) demuxer=\(String(describing: type(of: demuxer)), privacy: .public)"
            )
            stream = try await demuxer.open()
        } catch {
            stateMachine.apply(.fail(error.localizedDescription))
            var diagnostics = NativePlayerDiagnostics(
                playbackState: stateMachine.state.rawValue,
                mediaSourceID: resolution.mediaSource.id,
                byteSourceType: "HTTPRangeByteSource",
                container: probe.format,
                demuxer: "unavailable"
            )
            diagnostics.bufferedRanges = metrics.bufferedRanges
            diagnostics.networkMbps = metrics.readThroughputMbps
            diagnostics.failureReason = error.localizedDescription
            diagnostics.unsupportedModules = [error.localizedDescription]
            return NativeVLCPlaybackSnapshot(
                overlayLines: diagnostics.overlayLines,
                routeDescription: "NativeVLCClass(\(probe.format.rawValue))",
                playbackErrorMessage: error.localizedDescription
            )
        }
        stateMachine.apply(.planStarted)
        let plan = NativePlaybackPlanner(options: plannerOptions(from: nativeConfig)).makePlan(
            probe: probe,
            stream: stream,
            access: metrics
        )
        AppLog.playback.notice(
            "nativevlc.playbackPlan.created — source=\(resolution.mediaSource.id, privacy: .public) canStart=\(plan.canStartLocalPlayback, privacy: .public) demuxer=\(plan.demux.backend, privacy: .public) video=\(plan.video?.backend ?? "none", privacy: .public) audio=\(plan.audio?.backend ?? "none", privacy: .public)"
        )
        AppLog.playback.notice("nativevlc.serverTranscodeUsed \(resolution.serverTranscodeUsed, privacy: .public)")
        if plan.canStartLocalPlayback {
            stateMachine.apply(.bufferStarted)
        } else {
            stateMachine.apply(.fail(plan.diagnostics.failureReason ?? "No local native playback backend can start."))
        }
        var diagnostics = plan.diagnostics
        diagnostics.playbackState = stateMachine.state.rawValue
        diagnostics.mediaSourceID = resolution.mediaSource.id
        diagnostics.originalMediaRequested = resolution.originalMediaRequested
        diagnostics.serverTranscodeUsed = resolution.serverTranscodeUsed
        diagnostics.byteSourceType = "HTTPRangeByteSource"
        diagnostics.rendererBackend = plan.canStartLocalPlayback ? "AVSampleBufferDisplayLayer" : diagnostics.rendererBackend
        diagnostics.audioRendererBackend = plan.canStartLocalPlayback ? "AVSampleBufferAudioRenderer" : diagnostics.audioRendererBackend
        diagnostics.masterClock = plan.canStartLocalPlayback ? "AVSampleBufferRenderSynchronizer" : diagnostics.masterClock
        if probe.format == .mp4 || probe.format == .mov || probe.format == .matroska || probe.format == .webm || probe.format == .mpegTS || probe.format == .m2ts {
            let packetCounts = try? await inspectPackets(demuxer: demuxer, stream: stream, maxPackets: 24)
            diagnostics.videoPacketCount = packetCounts?.video ?? 0
            diagnostics.audioPacketCount = packetCounts?.audio ?? 0
        }
        let sharedTracks = stream.tracks.map(sharedTrack)
        let audio = sharedTracks.filter { track in stream.tracks.first(where: { "\($0.trackId)" == track.id })?.kind == .audio }
        let subtitles = sharedTracks.filter { track in stream.tracks.first(where: { "\($0.trackId)" == track.id })?.kind == .subtitle }
        let playbackURL = plan.canStartLocalPlayback ? resolution.url : nil
        let startTimeSeconds = startTimeTicks.map { Double($0) / 10_000_000 }
        return NativeVLCPlaybackSnapshot(
            overlayLines: diagnostics.overlayLines,
            routeDescription: "NativeVLCClass(\(probe.format.rawValue))",
            playbackURL: playbackURL,
            playbackHeaders: resolution.headers,
            startTimeSeconds: startTimeSeconds,
            playbackErrorMessage: plan.canStartLocalPlayback ? nil : diagnostics.failureReason,
            audioTracks: audio,
            subtitleTracks: subtitles,
            selectedAudioTrackID: audio.first(where: \.isDefault)?.id ?? audio.first?.id,
            selectedSubtitleTrackID: subtitles.first(where: \.isDefault)?.id
        )
    }

    private func plannerOptions(from config: NativeVLCClassPlayerConfig) -> NativePlaybackPlannerOptions {
        NativePlaybackPlannerOptions(
            allowServerTranscodeFallback: config.allowServerTranscodeFallback,
            preferAppleHardwareDecode: config.preferAppleHardwareDecode,
            allowCustomDemuxers: config.allowCustomDemuxers,
            allowSoftwareDecode: config.allowSoftwareDecode,
            enableMetalRenderer: config.enableMetalRenderer,
            enableExperimentalMKV: config.enableExperimentalMKV,
            enableExperimentalASS: config.enableExperimentalASS,
            enableExperimentalPGS: config.enableExperimentalPGS,
            enableExperimentalTrueHD: config.enableExperimentalTrueHD,
            enableExperimentalDTS: config.enableExperimentalDTS
        )
    }

    private func inspectPackets(
        demuxer: any MediaDemuxer,
        stream: DemuxerStreamInfo,
        maxPackets: Int
    ) async throws -> (video: Int, audio: Int) {
        let videoTrackIDs = Set(stream.tracks.filter { $0.kind == .video }.map(\.trackId))
        let audioTrackIDs = Set(stream.tracks.filter { $0.kind == .audio }.map(\.trackId))
        var video = 0
        var audio = 0

        for _ in 0..<maxPackets {
            guard let packet = try await demuxer.readNextPacket() else { break }
            if videoTrackIDs.contains(packet.trackID) {
                video += 1
            } else if audioTrackIDs.contains(packet.trackID) {
                audio += 1
            }
            if video > 0 && audio > 0 { break }
        }

        return (video, audio)
    }

    private func sharedTrack(_ track: NativeMediaCore.MediaTrack) -> Shared.MediaTrack {
        Shared.MediaTrack(
            id: "\(track.trackId)",
            title: track.title ?? "\(track.kind.rawValue.capitalized) \(track.trackId)",
            language: track.language,
            codec: track.codec,
            isDefault: track.isDefault,
            isForced: track.isForced,
            index: track.trackId
        )
    }
}
