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
    private let mediaGatewayStore: MediaGatewayStore?
    private let probeService = ContainerProbeService()
    private var stateMachine = NativePlaybackStateMachine()

    public init(
        apiClient: any JellyfinAPIClientProtocol & Sendable,
        resolver: OriginalMediaResolver = OriginalMediaResolver(authPolicy: .header),
        mediaGatewayStore: MediaGatewayStore? = nil
    ) {
        self.apiClient = apiClient
        self.resolver = resolver
        self.mediaGatewayStore = mediaGatewayStore
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
        let options = Self.originalPlaybackInfoOptions(
            nativeConfig: nativeConfig,
            startTimeTicks: startTimeTicks
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
            configuration: configuration,
            session: session,
            nativeConfig: nativeConfig,
            startTimeTicks: startTimeTicks
        )
    }

    private func prepareResolved(
        _ resolution: OriginalMediaResolution,
        configuration: ServerConfiguration,
        session: UserSession,
        nativeConfig: NativePlayerConfig,
        startTimeTicks: Int64?
    ) async throws -> NativePlayerPlaybackSnapshot {
        let originalHeaders = authenticatedOriginalHeaders(resolution: resolution, session: session)
        let originalURL = authenticatedOriginalURL(resolution: resolution, headers: originalHeaders)
        let shouldUseAppleNativeSurface = nativeConfig.surfacePreference == .directPlayWhenPossible
            && Self.shouldUseAppleNativeSurface(source: resolution.mediaSource, url: originalURL)

        if shouldUseAppleNativeSurface {
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

        let byteSource = makeByteSource(
            resolution: resolution,
            configuration: configuration,
            session: session,
            originalURL: originalURL,
            originalHeaders: originalHeaders
        )
        let source = byteSource.source
        AppLog.playback.notice(
            "nativeplayer.byteSource.open — source=\(resolution.mediaSource.id, privacy: .public) type=\(byteSource.type, privacy: .public)"
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
            ).makeDemuxer(format: probe.format, source: source, sourceURL: originalURL, sourceHeaders: originalHeaders)
            AppLog.playback.notice(
                "nativeplayer.demuxer.selected — source=\(resolution.mediaSource.id, privacy: .public) demuxer=\(String(describing: type(of: demuxer)), privacy: .public)"
            )
            stream = try await demuxer.open()
        } catch {
            stateMachine.apply(.fail(error.localizedDescription))
            var diagnostics = NativePlayerDiagnostics(
                playbackState: stateMachine.state.rawValue,
                mediaSourceID: resolution.mediaSource.id,
                byteSourceType: byteSource.type,
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
        diagnostics.byteSourceType = byteSource.type
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
           shouldUseAppleNativeSurface {
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

        let playbackURL = plan.canStartLocalPlayback ? originalURL : nil
        AppLog.playback.notice(
            "nativeplayer.sampleBuffer.route.selected — source=\(resolution.mediaSource.id, privacy: .public) avPlayerItem=false avPlayerViewController=false serverTranscodeUsed=\(resolution.serverTranscodeUsed, privacy: .public)"
        )
        return NativePlayerPlaybackSnapshot(
            overlayLines: diagnostics.overlayLines,
            routeDescription: "NativeEngine(\(probe.format.rawValue))",
            surface: .sampleBuffer,
            playbackURL: playbackURL,
            playbackHeaders: originalHeaders,
            startTimeSeconds: startTimeSeconds,
            playbackErrorMessage: plan.canStartLocalPlayback ? nil : diagnostics.failureReason,
            audioTracks: audio,
            subtitleTracks: subtitles,
            selectedAudioTrackID: audio.first(where: \.isDefault)?.id ?? audio.first?.id,
            selectedSubtitleTrackID: subtitles.first(where: \.isDefault)?.id
        )
    }

    private func makeByteSource(
        resolution: OriginalMediaResolution,
        configuration: ServerConfiguration,
        session: UserSession,
        originalURL: URL,
        originalHeaders: [String: String]
    ) -> (source: any MediaByteSource, type: String) {
        let upstream = HTTPRangeByteSource(url: originalURL, headers: originalHeaders)
        guard configuration.mediaCacheMode != .off, let mediaGatewayStore else {
            return (upstream, "HTTPRangeByteSource")
        }
        let key = MediaGatewayCacheKey(
            scope: "native-original",
            userID: session.userID,
            serverID: configuration.serverURL.host ?? configuration.serverURL.absoluteString,
            itemID: resolution.mediaSource.itemID,
            sourceID: resolution.mediaSource.id,
            routeURL: originalURL,
            routeHeaders: originalHeaders
        )
        let cached = CachingMediaByteSource(upstream: upstream, store: mediaGatewayStore, key: key)
        return (cached, "CachingMediaByteSource(HTTPRangeByteSource)")
    }

    private nonisolated func authenticatedOriginalHeaders(
        resolution: OriginalMediaResolution,
        session: UserSession
    ) -> [String: String] {
        resolution.headers.merging(PlaybackAuthenticationHeaders.jellyfin(token: session.token)) { current, _ in current }
    }

    private nonisolated func authenticatedOriginalURL(
        resolution: OriginalMediaResolution,
        headers: [String: String]
    ) -> URL {
        PlaybackAuthenticatedRequestURL.forInternalURLSession(resolution.url, headers: headers)
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
        if !url.isFileURL,
           let fileSize = source.fileSize,
           fileSize > maxRemoteAppleNativeProgressiveBytes {
            return false
        }

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

    private static let maxRemoteAppleNativeProgressiveBytes: Int64 = 8 * 1_024 * 1_024 * 1_024

    public nonisolated static func originalPlaybackInfoOptions(
        nativeConfig: NativePlayerConfig,
        startTimeTicks: Int64?
    ) -> PlaybackInfoOptions {
        PlaybackInfoOptions(
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
    }

    public nonisolated static func makeAppleNativeSelection(
        resolution: OriginalMediaResolution,
        session: UserSession
    ) -> PlaybackAssetSelection {
        var headers = resolution.headers
        headers.merge(PlaybackAuthenticationHeaders.jellyfin(token: session.token)) { current, _ in current }
        let assetURL = PlaybackAuthenticatedRequestURL.forInternalURLSession(resolution.url, headers: headers)
        let source = resolution.mediaSource
        let debugInfo = PlaybackDebugInfo(
            container: source.container ?? assetURL.pathExtension,
            videoCodec: source.videoCodec ?? "unknown",
            videoBitDepth: source.videoBitDepth,
            hdrMode: hdrMode(for: source),
            audioMode: source.audioCodec ?? "unknown",
            bitrate: source.bitrate,
            playMethod: "DirectPlay"
        )
        return PlaybackAssetSelection(
            source: source,
            decision: PlaybackDecision(sourceID: source.id, route: .directPlay(assetURL)),
            assetURL: assetURL,
            headers: headers,
            debugInfo: debugInfo
        )
    }

    public nonisolated static func makeAppleNativeSnapshot(
        selection: PlaybackAssetSelection,
        session: UserSession,
        startTimeTicks: Int64?
    ) -> NativePlayerPlaybackSnapshot {
        var preparedSelection = selection
        preparedSelection.headers.merge(PlaybackAuthenticationHeaders.jellyfin(token: session.token)) { current, _ in current }
        preparedSelection.assetURL = PlaybackAuthenticatedRequestURL.forInternalURLSession(
            preparedSelection.assetURL,
            headers: preparedSelection.headers
        )
        preparedSelection.decision = PlaybackDecision(
            sourceID: preparedSelection.source.id,
            route: .directPlay(preparedSelection.assetURL),
            playbackPlan: preparedSelection.decision.playbackPlan
        )
        let audio = preparedSelection.source.audioTracks
        let subtitles = preparedSelection.source.subtitleTracks
        return NativePlayerPlaybackSnapshot(
            overlayLines: appleNativeOverlayLines(for: preparedSelection),
            routeDescription: "Direct Play (Apple Native)",
            surface: .appleNative,
            playbackURL: nil,
            playbackHeaders: [:],
            startTimeSeconds: startTimeTicks.map { Double($0) / 10_000_000 },
            applePlaybackSelection: preparedSelection,
            audioTracks: audio,
            subtitleTracks: subtitles,
            selectedAudioTrackID: audio.first(where: \.isDefault)?.id ?? audio.first?.id,
            selectedSubtitleTrackID: subtitles.first(where: \.isDefault)?.id
        )
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
        Self.makeAppleNativeSelection(resolution: resolution, session: session)
    }

    private nonisolated static func appleNativeOverlayLines(for selection: PlaybackAssetSelection) -> [String] {
        let source = selection.source
        return [
            "state=apple-native-directplay",
            "mediaSource=\(source.id)",
            "container=\(source.container ?? "unknown")",
            "video=\(source.videoCodec ?? "unknown")",
            "audio=\(source.audioCodec ?? "unknown")",
            "originalMediaRequested=true",
            "serverTranscodeUsed=false",
            "nativeProbe=false",
            "renderer=AVPlayerViewController"
        ]
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

    private nonisolated static func hdrMode(for source: MediaSource) -> HDRPlaybackMode {
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
