import Foundation
import NativeMediaCore
import Shared

public enum NativePlayerPlaybackSurface: String, Sendable, Equatable {
    case appleNative
    case sampleBuffer
}

public enum NativePlayerPreparationError: LocalizedError, Sendable, Equatable {
    case appleNativeContainerRequiresCoordinatorFallback(String)

    public var errorDescription: String? {
        switch self {
        case let .appleNativeContainerRequiresCoordinatorFallback(reason):
            return "Apple-native container requires coordinator fallback: \(reason)"
        }
    }
}

public struct NativePlayerEvidenceContext: Sendable, Equatable {
    public let session: String
    public let media: String
    public let source: String

    public init(session: String, media: String, source: String) {
        self.session = session
        self.media = media
        self.source = source
    }
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
    public var audioTrackDisplayHints: [Shared.MediaTrack]
    public var subtitleTrackDisplayHints: [Shared.MediaTrack]
    public var selectedAudioTrackID: String?
    public var selectedSubtitleTrackID: String?
    public var evidenceContext: NativePlayerEvidenceContext?

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
        audioTrackDisplayHints: [Shared.MediaTrack] = [],
        subtitleTrackDisplayHints: [Shared.MediaTrack] = [],
        selectedAudioTrackID: String? = nil,
        selectedSubtitleTrackID: String? = nil,
        evidenceContext: NativePlayerEvidenceContext? = nil
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
        self.audioTrackDisplayHints = audioTrackDisplayHints
        self.subtitleTrackDisplayHints = subtitleTrackDisplayHints
        self.selectedAudioTrackID = selectedAudioTrackID
        self.selectedSubtitleTrackID = selectedSubtitleTrackID
        self.evidenceContext = evidenceContext
    }
}

public actor NativePlayerPlaybackController {
    public typealias ByteSourceFactory = @Sendable (
        _ url: URL,
        _ headers: [String: String]
    ) -> any MediaByteSource

    private let apiClient: any JellyfinAPIClientProtocol & Sendable
    private let resolver: OriginalMediaResolver
    private let mediaGatewayStore: MediaGatewayStore?
    private let byteSourceFactory: ByteSourceFactory
    private let probeService = ContainerProbeService()
    private var stateMachine = NativePlaybackStateMachine()

    public init(
        apiClient: any JellyfinAPIClientProtocol & Sendable,
        resolver: OriginalMediaResolver = OriginalMediaResolver(authPolicy: .header),
        mediaGatewayStore: MediaGatewayStore? = nil,
        byteSourceFactory: @escaping ByteSourceFactory = { HTTPRangeByteSource(url: $0, headers: $1) }
    ) {
        self.apiClient = apiClient
        self.resolver = resolver
        self.mediaGatewayStore = mediaGatewayStore
        self.byteSourceFactory = byteSourceFactory
    }

    public func prepare(
        itemID: String,
        configuration: ServerConfiguration,
        session: UserSession,
        nativeConfig: NativePlayerConfig,
        startTimeTicks: Int64?
    ) async throws -> NativePlayerPlaybackSnapshot {
        let evidenceSession = AppLogFormat.randomSessionIdentifier()
        let mediaCorrelation = AppLogFormat.correlationIdentifier(itemID, domain: .media)
        AppLog.playback.notice("nativeplayer.original.resolve.start — media=\(mediaCorrelation, privacy: .public)")
        stateMachine.apply(.beginResolve)
        let options = Self.originalPlaybackInfoOptions(
            nativeConfig: nativeConfig,
            startTimeTicks: startTimeTicks
        )
        let sessionScope = PlaybackCoordinator.AuthenticatedSessionScope(
            server: configuration.serverURL.absoluteString,
            userID: session.userID,
            token: session.token
        )
        let handoffSource = await NativeOriginalSourceHandoffStore.shared.consume(
            for: .init(
                itemID: itemID,
                startTimeTicks: startTimeTicks,
                session: sessionScope
            )
        )
        let sources: [MediaSource]
        if let handoffSource {
            sources = [handoffSource]
            AppLog.playback.notice(
                "nativeplayer.original.resolve.handoff_hit — media=\(mediaCorrelation, privacy: .public)"
            )
        } else {
            sources = try await apiClient.fetchPlaybackSources(itemID: itemID, options: options)
        }
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
            "nativeplayer.original.resolve.ok — media=\(mediaCorrelation, privacy: .public) source=\(AppLogFormat.correlationIdentifier(resolution.mediaSource.id, domain: .source), privacy: .public) selectedPath=original_stream"
        )
        let evidenceContext = NativePlayerEvidenceContext(
            session: evidenceSession,
            media: mediaCorrelation,
            source: AppLogFormat.correlationIdentifier(resolution.mediaSource.id, domain: .source)
        )
        stateMachine.apply(.originalResolved)
        if handoffSource != nil {
            return makeTrustedNativeHandoffSnapshot(
                resolution,
                session: session,
                startTimeTicks: startTimeTicks,
                evidenceContext: evidenceContext
            )
        }
        return try await prepareResolved(
            resolution,
            configuration: configuration,
            session: session,
            nativeConfig: nativeConfig,
            startTimeTicks: startTimeTicks,
            evidenceContext: evidenceContext
        )
    }

    private func makeTrustedNativeHandoffSnapshot(
        _ resolution: OriginalMediaResolution,
        session: UserSession,
        startTimeTicks: Int64?,
        evidenceContext: NativePlayerEvidenceContext
    ) -> NativePlayerPlaybackSnapshot {
        let headers = authenticatedOriginalHeaders(resolution: resolution, session: session)
        let url = authenticatedOriginalURL(resolution: resolution, headers: headers)
        stateMachine.apply(.bufferStarted)
        PlayerDeepEvidenceSink.append(
            event: .plan,
            session: evidenceContext.session,
            media: evidenceContext.media,
            source: evidenceContext.source,
            fields: [
                .canStart: .boolean(true),
                .demuxer: .category(.matroska),
                .videoBackend: .category(.videoToolbox),
                .audioBackend: .category(.sampleBufferAudioRenderer),
            ]
        )
        PlayerDeepEvidenceSink.append(
            event: .routeSelection,
            session: evidenceContext.session,
            media: evidenceContext.media,
            source: evidenceContext.source,
            fields: [
                .route: .category(.sampleBuffer),
                .avPlayerItem: .boolean(false),
                .avPlayerViewController: .boolean(false),
                .serverTranscodeUsed: .boolean(resolution.serverTranscodeUsed),
            ]
        )
        AppLog.playback.notice(
            "nativeplayer.sampleBuffer.route.selected — source=\(evidenceContext.source, privacy: .public) handoffPrepared=true nativeProbe=false avPlayerItem=false avPlayerViewController=false serverTranscodeUsed=false"
        )
        return NativePlayerPlaybackSnapshot(
            overlayLines: [
                "playbackState=buffering",
                "container=matroska",
                "demuxer=surface-owned",
                "originalMediaRequested=true",
                "serverTranscodeUsed=false"
            ],
            routeDescription: "NativeEngine(matroska)",
            surface: .sampleBuffer,
            playbackURL: url,
            playbackHeaders: headers,
            startTimeSeconds: startTimeTicks.map { Double($0) / 10_000_000 },
            // Jellyfin IDs (`track-<stream index>`) are not Matroska EBML TrackNumber values.
            // The one surface-owned demux open publishes verified native IDs back to the session.
            audioTracks: [],
            subtitleTracks: [],
            audioTrackDisplayHints: resolution.mediaSource.audioTracks,
            subtitleTrackDisplayHints: resolution.mediaSource.subtitleTracks,
            selectedAudioTrackID: nil,
            selectedSubtitleTrackID: nil,
            evidenceContext: evidenceContext
        )
    }

    private func prepareResolved(
        _ resolution: OriginalMediaResolution,
        configuration: ServerConfiguration,
        session: UserSession,
        nativeConfig: NativePlayerConfig,
        startTimeTicks: Int64?,
        evidenceContext: NativePlayerEvidenceContext
    ) async throws -> NativePlayerPlaybackSnapshot {
        let mediaCorrelation = evidenceContext.media
        let sourceCorrelation = evidenceContext.source
        let originalHeaders = authenticatedOriginalHeaders(resolution: resolution, session: session)
        let originalURL = authenticatedOriginalURL(resolution: resolution, headers: originalHeaders)
        let prefersDirectAppleSurface = nativeConfig.surfacePreference == .directPlayWhenPossible
        // Dolby Vision / HDR must use the Apple-native surface (AVPlayerViewController). The
        // experimental sample-buffer renderer has no EDR / DV tone-mapping on iOS and renders
        // HDR/DV very dark; AVPlayer renders it correctly on both iOS and tvOS. So force the
        // Apple-native surface for an Apple-native HDR/DV container regardless of the user's
        // surface preference (e.g. "Always Custom Player").
        let isHDRorDV = Self.hdrMode(for: resolution.mediaSource) != .sdr
        let mustUseAppleForHDR = isHDRorDV
            && Self.isAppleNativeContainer(source: resolution.mediaSource, url: originalURL)
        let shouldUseAppleNativeSurface = (prefersDirectAppleSurface || mustUseAppleForHDR)
            && Self.shouldUseAppleNativeSurface(source: resolution.mediaSource, url: originalURL)

        if shouldUseAppleNativeSurface {
            let audio = resolution.mediaSource.audioTracks
            let subtitles = resolution.mediaSource.subtitleTracks
            let selection = makeAppleNativeSelection(
                resolution: resolution,
                session: session
            )
            AppLog.playback.notice(
                "nativeplayer.apple.route.selected — source=\(sourceCorrelation, privacy: .public) route=directPlay avPlayerItem=true avPlayerViewController=true nativeProbe=false serverTranscodeUsed=\(resolution.serverTranscodeUsed, privacy: .public)"
            )
            PlayerDeepEvidenceSink.append(
                event: .routeSelection,
                session: evidenceContext.session,
                media: mediaCorrelation,
                source: sourceCorrelation,
                fields: [
                    .route: .category(.directPlay),
                    .avPlayerItem: .boolean(true),
                    .avPlayerViewController: .boolean(true),
                    .serverTranscodeUsed: .boolean(resolution.serverTranscodeUsed),
                ]
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
                selectedSubtitleTrackID: subtitles.first(where: \.isDefault)?.id,
                evidenceContext: evidenceContext
            )
        }

        if prefersDirectAppleSurface || mustUseAppleForHDR,
           Self.isAppleNativeContainer(source: resolution.mediaSource, url: originalURL) {
            let reason = mustUseAppleForHDR && !prefersDirectAppleSurface
                ? "hdr_dv_requires_apple_surface"
                : Self.appleNativeSurfaceRejectionReason(source: resolution.mediaSource, url: originalURL)
            AppLog.playback.warning(
                "nativeplayer.apple.route.rejected — source=\(sourceCorrelation, privacy: .public) fallback=coordinator reason=\(reason, privacy: .public)"
            )
            throw NativePlayerPreparationError.appleNativeContainerRequiresCoordinatorFallback(reason)
        }

        let byteSource = makeByteSource(
            resolution: resolution,
            configuration: configuration,
            session: session,
            originalURL: originalURL,
            originalHeaders: originalHeaders
        )
        let source = byteSource.source
        return try await withTemporaryByteSource(source) {
        AppLog.playback.notice(
            "nativeplayer.byteSource.open — source=\(sourceCorrelation, privacy: .public) type=\(byteSource.type, privacy: .public)"
        )
        stateMachine.apply(.probeStarted)
        AppLog.playback.notice("nativeplayer.probe.start — source=\(sourceCorrelation, privacy: .public)")
        let probe = try await probeService.probe(source: source, hint: resolution.mediaSource.container)
        AppLog.playback.notice(
            "nativeplayer.probe.result — source=\(sourceCorrelation, privacy: .public) format=\(probe.format.rawValue, privacy: .public) confidence=\(probe.confidence.rawValue, privacy: .public)"
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
                "nativeplayer.demuxer.selected — source=\(sourceCorrelation, privacy: .public) demuxer=\(String(describing: type(of: demuxer)), privacy: .public)"
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
                startTimeSeconds: startTimeTicks.map { Double($0) / 10_000_000 },
                playbackErrorMessage: error.localizedDescription,
                evidenceContext: evidenceContext
            )
        }
        stateMachine.apply(.planStarted)
        let plan = NativePlaybackPlanner(options: plannerOptions(from: nativeConfig)).makePlan(
            probe: probe,
            stream: stream,
            access: metrics
        )
        PlayerDeepEvidenceSink.append(
            event: .plan,
            session: evidenceContext.session,
            media: mediaCorrelation,
            source: sourceCorrelation,
            fields: [
                .canStart: .boolean(plan.canStartLocalPlayback),
                .demuxer: .category(.normalized(plan.demux.backend)),
                .videoBackend: .category(.normalized(plan.video?.backend)),
                .audioBackend: .category(.normalized(plan.audio?.backend)),
            ]
        )
        AppLog.playback.notice(
            "nativeplayer.playbackPlan.created — source=\(sourceCorrelation, privacy: .public) canStart=\(plan.canStartLocalPlayback, privacy: .public) demuxer=\(plan.demux.backend, privacy: .public) video=\(plan.video?.backend ?? "none", privacy: .public) audio=\(plan.audio?.backend ?? "none", privacy: .public)"
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
        let audio = Self.presentableNativeTracks(
            stream.tracks.filter { $0.kind == .audio },
            metadataTracks: resolution.mediaSource.audioTracks
        )
        let subtitles = Self.presentableNativeTracks(
            stream.tracks.filter { $0.kind == .subtitle },
            metadataTracks: resolution.mediaSource.subtitleTracks
        )
        let startTimeSeconds = startTimeTicks.map { Double($0) / 10_000_000 }

        if plan.canStartLocalPlayback,
           shouldUseAppleNativeSurface {
            let selection = makeAppleNativeSelection(
                resolution: resolution,
                session: session
            )
            AppLog.playback.notice(
                "nativeplayer.apple.route.selected — source=\(sourceCorrelation, privacy: .public) route=directPlay avPlayerItem=true avPlayerViewController=true nativeProbe=true serverTranscodeUsed=\(resolution.serverTranscodeUsed, privacy: .public)"
            )
            PlayerDeepEvidenceSink.append(
                event: .routeSelection,
                session: evidenceContext.session,
                media: mediaCorrelation,
                source: sourceCorrelation,
                fields: [
                    .route: .category(.directPlay),
                    .avPlayerItem: .boolean(true),
                    .avPlayerViewController: .boolean(true),
                    .serverTranscodeUsed: .boolean(resolution.serverTranscodeUsed),
                ]
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
                selectedSubtitleTrackID: subtitles.first(where: \.isDefault)?.id,
                evidenceContext: evidenceContext
            )
        }

        // Last line of defense for non-Apple-native HDR/DV (e.g. Matroska): the sample-buffer
        // surface cannot tone-map Dolby Vision/HDR on iOS and would render dark. Route to the
        // DV-aware coordinator fallback instead. tvOS keeps the sample-buffer surface (its
        // dynamic range is driven by AVDisplayCriteria).
        if Self.sampleBufferShouldRejectHDR(for: resolution.mediaSource) {
            AppLog.playback.warning(
                "nativeplayer.sampleBuffer.route.rejected_hdr — source=\(sourceCorrelation, privacy: .public) fallback=coordinator reason=hdr_dv_unsupported_on_sample_buffer"
            )
            throw NativePlayerPreparationError.appleNativeContainerRequiresCoordinatorFallback("hdr_dv_unsupported_on_sample_buffer")
        }

        let playbackURL = plan.canStartLocalPlayback ? originalURL : nil
        PlayerDeepEvidenceSink.append(
            event: .routeSelection,
            session: evidenceContext.session,
            media: mediaCorrelation,
            source: sourceCorrelation,
            fields: [
                .route: .category(.sampleBuffer),
                .avPlayerItem: .boolean(false),
                .avPlayerViewController: .boolean(false),
                .serverTranscodeUsed: .boolean(resolution.serverTranscodeUsed),
            ]
        )
        AppLog.playback.notice(
            "nativeplayer.sampleBuffer.route.selected — source=\(sourceCorrelation, privacy: .public) avPlayerItem=false avPlayerViewController=false serverTranscodeUsed=\(resolution.serverTranscodeUsed, privacy: .public)"
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
            audioTrackDisplayHints: resolution.mediaSource.audioTracks,
            subtitleTrackDisplayHints: resolution.mediaSource.subtitleTracks,
            selectedAudioTrackID: audio.first(where: \.isDefault)?.id ?? audio.first?.id,
            selectedSubtitleTrackID: subtitles.first(where: \.isDefault)?.id,
            evidenceContext: evidenceContext
        )
        }
    }

    private func withTemporaryByteSource<Result>(
        _ source: any MediaByteSource,
        operation: () async throws -> Result
    ) async throws -> Result {
        do {
            let result = try await operation()
            await source.cancel()
            return result
        } catch {
            await source.cancel()
            throw error
        }
    }

    private func makeByteSource(
        resolution: OriginalMediaResolution,
        configuration: ServerConfiguration,
        session: UserSession,
        originalURL: URL,
        originalHeaders: [String: String]
    ) -> (source: any MediaByteSource, type: String) {
        let upstream = byteSourceFactory(originalURL, originalHeaders)
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
        let capabilities = DeviceCapabilities()
        guard isAppleNativeContainer(source: source, url: url, capabilities: capabilities) else {
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

    public nonisolated static func isAppleNativeContainer(
        source: MediaSource,
        url: URL
    ) -> Bool {
        isAppleNativeContainer(source: source, url: url, capabilities: DeviceCapabilities())
    }

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

    private nonisolated static func isAppleNativeContainer(
        source: MediaSource,
        url: URL,
        capabilities: DeviceCapabilities
    ) -> Bool {
        normalizedContainers(source.container, fallbackURL: url)
            .contains { capabilities.directPlayableContainers.contains($0) }
    }

    private nonisolated static func appleNativeSurfaceRejectionReason(
        source: MediaSource,
        url: URL
    ) -> String {
        let capabilities = DeviceCapabilities()
        guard isAppleNativeContainer(source: source, url: url, capabilities: capabilities) else {
            return "container_not_apple_native"
        }

        let videoCodec = source.normalizedVideoCodec
        if !videoCodec.isEmpty, !isAppleNativeVideoCodec(videoCodec, capabilities: capabilities) {
            return "unsupported_video_codec:\(videoCodec)"
        }

        let audioCodec = source.normalizedAudioCodec
        if audioCodec.isEmpty || capabilities.audioCodecs.contains(audioCodec) {
            return "unknown"
        }
        let supportedTrack = source.audioTracks.contains { track in
            guard let codec = track.codec?.lowercased(), !codec.isEmpty else { return false }
            return capabilities.audioCodecs.contains(codec)
        }
        return supportedTrack ? "unknown" : "unsupported_audio_codec:\(audioCodec)"
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
            "mediaSource=\(AppLogFormat.correlationIdentifier(source.id, domain: .source))",
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
            "mediaSource=\(AppLogFormat.correlationIdentifier(source.id, domain: .source))",
            "container=\(source.container ?? "unknown")",
            "video=\(source.videoCodec ?? "unknown")",
            "audio=\(source.audioCodec ?? "unknown")",
            "originalMediaRequested=\(resolution.originalMediaRequested)",
            "serverTranscodeUsed=\(resolution.serverTranscodeUsed)",
            "nativeProbe=false",
            "renderer=AVPlayerViewController"
        ]
    }

    /// Whether the experimental sample-buffer surface would render this source's HDR/DV
    /// incorrectly and should be refused in favour of the Apple-native coordinator fallback.
    /// iOS: the renderer wires no EDR / DV tone-mapping, so HDR/DV renders dark — reject.
    /// tvOS: the display's dynamic range is set via AVDisplayCriteria, so it is acceptable.
    nonisolated static func sampleBufferShouldRejectHDR(for source: MediaSource) -> Bool {
        #if os(tvOS)
        _ = source
        return false
        #else
        // Reject only on genuine HDR/DV signalling. 10-bit SDR (Main10) renders correctly on the
        // sample-buffer surface, so it must NOT be diverted to the coordinator fallback.
        return hdrMode(for: source) != .sdr
        #endif
    }

    nonisolated static func hdrMode(for source: MediaSource) -> HDRPlaybackMode {
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
        if source.hasExplicitHDRorDVSignaling {
            return .hdr10
        }
        return .sdr
    }

    nonisolated static func presentableNativeTracks(
        _ nativeTracks: [NativeMediaCore.MediaTrack],
        metadataTracks: [Shared.MediaTrack]
    ) -> [Shared.MediaTrack] {
        nativeTracks.enumerated().map { index, nativeTrack in
            let metadata = metadataTracks[safe: index]
            return Shared.MediaTrack(
                id: "\(nativeTrack.trackId)",
                title: metadata?.title ?? nativeTrack.title ?? "\(nativeTrack.kind.rawValue.capitalized) \(nativeTrack.trackId)",
                language: metadata?.language ?? nativeTrack.language,
                codec: metadata?.codec ?? nativeTrack.codec,
                isDefault: metadata?.isDefault ?? nativeTrack.isDefault,
                isForced: metadata?.isForced ?? nativeTrack.isForced,
                index: nativeTrack.trackId
            )
        }
    }

}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
