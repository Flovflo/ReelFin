import Foundation
import NativeMediaCore
import Shared

public enum NativePlayerPlaybackSurface: String, Sendable, Equatable {
    case appleNative
    case sampleBuffer
}

public struct NativePlayerPlaybackSnapshot: Sendable {
    public var overlayLines: [String]
    public var routeDescription: String
    public var surface: NativePlayerPlaybackSurface
    public var playbackURL: URL?
    public var playbackHeaders: [String: String]
    public var startTimeSeconds: Double?
    public var playbackErrorMessage: String?
    public var applePlaybackSelection: PlaybackAssetSelection?
    public var nativeBridgePlan: NativeBridgePlan?
    public var audioTracks: [Shared.MediaTrack]
    public var subtitleTracks: [Shared.MediaTrack]
    public var selectedAudioTrackID: String?
    public var selectedSubtitleTrackID: String?

    public init(
        overlayLines: [String],
        routeDescription: String,
        surface: NativePlayerPlaybackSurface = .sampleBuffer,
        playbackURL: URL? = nil,
        playbackHeaders: [String: String] = [:],
        startTimeSeconds: Double? = nil,
        playbackErrorMessage: String? = nil,
        applePlaybackSelection: PlaybackAssetSelection? = nil,
        nativeBridgePlan: NativeBridgePlan? = nil,
        audioTracks: [Shared.MediaTrack] = [],
        subtitleTracks: [Shared.MediaTrack] = [],
        selectedAudioTrackID: String? = nil,
        selectedSubtitleTrackID: String? = nil
    ) {
        self.overlayLines = overlayLines
        self.routeDescription = routeDescription
        self.surface = surface
        self.playbackURL = playbackURL
        self.playbackHeaders = playbackHeaders
        self.startTimeSeconds = startTimeSeconds
        self.playbackErrorMessage = playbackErrorMessage
        self.applePlaybackSelection = applePlaybackSelection
        self.nativeBridgePlan = nativeBridgePlan
        self.audioTracks = audioTracks
        self.subtitleTracks = subtitleTracks
        self.selectedAudioTrackID = selectedAudioTrackID
        self.selectedSubtitleTrackID = selectedSubtitleTrackID
    }
}

public actor NativePlayerPlaybackController {
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
        nativeConfig: NativePlayerConfig,
        startTimeTicks: Int64?
    ) async throws -> NativePlayerPlaybackSnapshot {
        AppLog.playback.notice("nativeplayer.original.resolve.start — item=\(AppLogFormat.shortIdentifier(itemID), privacy: .public)")
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
        if let violation = NativePlayerRouteGuard.validateOriginalPlaybackURL(resolution.url).first {
            throw violation
        }
        AppLog.playback.notice(
            "nativeplayer.original.resolve.ok — item=\(AppLogFormat.shortIdentifier(itemID), privacy: .public) source=\(resolution.mediaSource.id, privacy: .public) selectedPath=\(resolution.selectedPath, privacy: .public)"
        )
        stateMachine.apply(.originalResolved)
        return try await prepareResolved(
            resolution,
            session: session,
            nativeConfig: nativeConfig,
            startTimeTicks: startTimeTicks
        )
    }

    private func prepareResolved(
        _ resolution: OriginalMediaResolution,
        session: UserSession,
        nativeConfig: NativePlayerConfig,
        startTimeTicks: Int64?
    ) async throws -> NativePlayerPlaybackSnapshot {
        if Self.shouldUseAppleNativeSurface(source: resolution.mediaSource, url: resolution.url) {
            let audio = resolution.mediaSource.audioTracks
            let subtitles = resolution.mediaSource.subtitleTracks
            let selection = makeAppleNativeSelection(
                resolution: resolution,
                session: session
            )
            AppLog.playback.notice(
                "nativeplayer.apple.route.selected — source=\(resolution.mediaSource.id, privacy: .public) route=directPlay avPlayerItem=true avPlayerViewController=true nativeProbe=false serverTranscodeUsed=\(resolution.serverTranscodeUsed, privacy: .public)"
            )
            return NativePlayerPlaybackSnapshot(
                overlayLines: appleNativeOverlayLines(for: resolution),
                routeDescription: "Direct Play (Apple Native)",
                surface: .appleNative,
                playbackURL: nil,
                playbackHeaders: [:],
                startTimeSeconds: startTimeTicks.map { Double($0) / 10_000_000 },
                applePlaybackSelection: selection,
                audioTracks: audio,
                subtitleTracks: subtitles,
                selectedAudioTrackID: audio.first(where: \.isDefault)?.id ?? audio.first?.id,
                selectedSubtitleTrackID: subtitles.first(where: \.isDefault)?.id
            )
        }

        let source = HTTPRangeByteSource(url: resolution.url, headers: resolution.headers)
        AppLog.playback.notice(
            "nativeplayer.byteSource.open — source=\(resolution.mediaSource.id, privacy: .public) type=HTTPRangeByteSource"
        )
        stateMachine.apply(.probeStarted)
        AppLog.playback.notice("nativeplayer.probe.start — source=\(resolution.mediaSource.id, privacy: .public)")
        let probe = try await probeService.probe(source: source, hint: resolution.mediaSource.container)
        AppLog.playback.notice(
            "nativeplayer.probe.result — source=\(resolution.mediaSource.id, privacy: .public) format=\(probe.format.rawValue, privacy: .public) confidence=\(probe.confidence.rawValue, privacy: .public)"
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
                "nativeplayer.demuxer.selected — source=\(resolution.mediaSource.id, privacy: .public) demuxer=\(String(describing: type(of: demuxer)), privacy: .public)"
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
            return NativePlayerPlaybackSnapshot(
                overlayLines: diagnostics.overlayLines,
                routeDescription: "NativeEngine(\(probe.format.rawValue))",
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
            "nativeplayer.playbackPlan.created — source=\(resolution.mediaSource.id, privacy: .public) canStart=\(plan.canStartLocalPlayback, privacy: .public) demuxer=\(plan.demux.backend, privacy: .public) video=\(plan.video?.backend ?? "none", privacy: .public) audio=\(plan.audio?.backend ?? "none", privacy: .public)"
        )
        AppLog.playback.notice("nativeplayer.serverTranscodeUsed \(resolution.serverTranscodeUsed, privacy: .public)")
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
        let startTimeSeconds = startTimeTicks.map { Double($0) / 10_000_000 }

        if plan.canStartLocalPlayback,
           Self.shouldUseAppleNativeSurface(source: resolution.mediaSource, url: resolution.url) {
            let selection = makeAppleNativeSelection(
                resolution: resolution,
                session: session
            )
            AppLog.playback.notice(
                "nativeplayer.apple.route.selected — source=\(resolution.mediaSource.id, privacy: .public) route=directPlay avPlayerItem=true avPlayerViewController=true nativeProbe=true serverTranscodeUsed=\(resolution.serverTranscodeUsed, privacy: .public)"
            )
            return NativePlayerPlaybackSnapshot(
                overlayLines: diagnostics.overlayLines,
                routeDescription: "Direct Play (Apple Native)",
                surface: .appleNative,
                playbackURL: nil,
                playbackHeaders: [:],
                startTimeSeconds: startTimeSeconds,
                applePlaybackSelection: selection,
                audioTracks: audio,
                subtitleTracks: subtitles,
                selectedAudioTrackID: audio.first(where: \.isDefault)?.id ?? audio.first?.id,
                selectedSubtitleTrackID: subtitles.first(where: \.isDefault)?.id
            )
        }

        let playbackURL = plan.canStartLocalPlayback ? resolution.url : nil
        AppLog.playback.notice(
            "nativeplayer.sampleBuffer.route.selected — source=\(resolution.mediaSource.id, privacy: .public) avPlayerItem=false avPlayerViewController=false serverTranscodeUsed=\(resolution.serverTranscodeUsed, privacy: .public)"
        )
        return NativePlayerPlaybackSnapshot(
            overlayLines: diagnostics.overlayLines,
            routeDescription: "NativeEngine(\(probe.format.rawValue))",
            surface: .sampleBuffer,
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

    private func plannerOptions(from config: NativePlayerConfig) -> NativePlaybackPlannerOptions {
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

    public nonisolated static func shouldUseAppleNativeSurface(
        source: MediaSource,
        url: URL
    ) -> Bool {
        let capabilities = DeviceCapabilities()
        let containers = normalizedContainers(source.container, fallbackURL: url)
        guard containers.contains(where: { capabilities.directPlayableContainers.contains($0) }) else {
            return false
        }

        let videoCodec = source.normalizedVideoCodec
        if !videoCodec.isEmpty, !isAppleNativeVideoCodec(videoCodec, capabilities: capabilities) {
            return false
        }

        let audioCodec = source.normalizedAudioCodec
        let sourceAudioSupported = audioCodec.isEmpty || capabilities.audioCodecs.contains(audioCodec)
        let anyTrackSupported = source.audioTracks.contains { track in
            guard let codec = track.codec?.lowercased(), !codec.isEmpty else { return false }
            return capabilities.audioCodecs.contains(codec)
        }
        return sourceAudioSupported || anyTrackSupported
    }

    private nonisolated static func isAppleNativeVideoCodec(
        _ codec: String,
        capabilities: DeviceCapabilities
    ) -> Bool {
        let normalized = codec.lowercased()
        if capabilities.videoCodecs.contains(normalized) {
            return true
        }
        if normalized == "hvc1" || normalized == "hev1" {
            return capabilities.videoCodecs.contains("hevc")
        }
        if normalized == "avc3" {
            return capabilities.videoCodecs.contains("h264") || capabilities.videoCodecs.contains("avc1")
        }
        return false
    }

    private nonisolated static func normalizedContainers(_ rawContainer: String?, fallbackURL: URL) -> [String] {
        if let rawContainer, !rawContainer.isEmpty {
            let tokens = rawContainer
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            if !tokens.isEmpty {
                return tokens
            }
        }

        let ext = fallbackURL.pathExtension.lowercased()
        return ext.isEmpty ? [] : [ext]
    }

    private func makeAppleNativeSelection(
        resolution: OriginalMediaResolution,
        session: UserSession
    ) -> PlaybackAssetSelection {
        var headers = resolution.headers
        headers["X-Emby-Token"] = session.token
        let source = resolution.mediaSource
        let debugInfo = PlaybackDebugInfo(
            container: source.container ?? resolution.url.pathExtension,
            videoCodec: source.videoCodec ?? "unknown",
            videoBitDepth: source.videoBitDepth,
            hdrMode: hdrMode(for: source),
            audioMode: source.audioCodec ?? "unknown",
            bitrate: source.bitrate,
            playMethod: "DirectPlay"
        )
        return PlaybackAssetSelection(
            source: source,
            decision: PlaybackDecision(sourceID: source.id, route: .directPlay(resolution.url)),
            assetURL: resolution.url,
            headers: headers,
            debugInfo: debugInfo
        )
    }

    private func appleNativeOverlayLines(for resolution: OriginalMediaResolution) -> [String] {
        let source = resolution.mediaSource
        return [
            "state=apple-native-directplay",
            "mediaSource=\(source.id)",
            "container=\(source.container ?? "unknown")",
            "video=\(source.videoCodec ?? "unknown")",
            "audio=\(source.audioCodec ?? "unknown")",
            "originalMediaRequested=\(resolution.originalMediaRequested)",
            "serverTranscodeUsed=\(resolution.serverTranscodeUsed)",
            "nativeProbe=false",
            "renderer=AVPlayerViewController"
        ]
    }

    private func hdrMode(for source: MediaSource) -> HDRPlaybackMode {
        let rangeType = (source.videoRangeType ?? "").lowercased()
        let range = (source.videoRange ?? "").lowercased()
        let codec = source.normalizedVideoCodec
        if (source.dvProfile ?? 0) > 0
            || rangeType.contains("dovi")
            || range.contains("dolby")
            || codec.contains("dvhe")
            || codec.contains("dvh1") {
            return .dolbyVision
        }
        if source.isLikelyHDRorDV {
            return .hdr10
        }
        return .sdr
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
