@testable import PlaybackEngine
import Shared
import XCTest

final class PlaybackPolicyTests: XCTestCase {
    func testRecoveryPlanOriginalLockNeverFallsBackToH264WhenDisabled() {
        let profiles = PlaybackSessionController.recoveryPlan(
            after: .serverDefault,
            policy: .originalLockHDRDV,
            allowSDRFallback: false
        )

        XCTAssertEqual(profiles, [.appleOptimizedHEVC])
        XCTAssertFalse(profiles.contains(.forceH264Transcode))
    }

    func testRecoveryPlanAutoIncludesH264FallbackWhenAllowed() {
        let profiles = PlaybackSessionController.recoveryPlan(
            after: .serverDefault,
            policy: .auto,
            allowSDRFallback: true
        )

        XCTAssertEqual(profiles, [.appleOptimizedHEVC, .forceH264Transcode])
    }

    func testRecoveryPlanAppleOptimizedFallsToConservativeThenH264() {
        let profiles = PlaybackSessionController.recoveryPlan(
            after: .appleOptimizedHEVC,
            policy: .auto,
            allowSDRFallback: true
        )

        XCTAssertEqual(profiles, [.conservativeCompatibility, .forceH264Transcode])
    }

    func testRecoveryPlanAppleOptimizedNoSDRFallbackUsesConservativeOnly() {
        let profiles = PlaybackSessionController.recoveryPlan(
            after: .appleOptimizedHEVC,
            policy: .auto,
            allowSDRFallback: false
        )

        XCTAssertEqual(profiles, [.conservativeCompatibility])
    }

    func testInitialProfilePromotesStoredH264FallbackToHEVCForDolbyVisionItems() {
        let profile = PlaybackSessionController.initialProfile(
            stored: .forceH264Transcode,
            playbackPolicy: .auto,
            allowSDRFallback: true,
            itemHasDolbyVision: true
        )

        XCTAssertEqual(profile, .appleOptimizedHEVC)
    }

    func testInitialProfileKeepsStoredH264FallbackForNonDolbyVisionItems() {
        let profile = PlaybackSessionController.initialProfile(
            stored: .forceH264Transcode,
            playbackPolicy: .auto,
            allowSDRFallback: true,
            itemHasDolbyVision: false
        )

        XCTAssertEqual(profile, .forceH264Transcode)
    }

    func testPreemptiveH264FallbackTriggersForUnsafeHEVCFMP4Packaging() {
        let source = MediaSource(
            id: "source-sdr",
            itemID: "item-sdr",
            name: "SDR Source",
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "eac3",
            videoRange: "SDR",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: URL(string: "https://example.com/master.m3u8")
        )

        let shouldFallback = PlaybackSessionController.shouldPreferForceH264Fallback(
            transport: "fMP4",
            hasInitMap: false,
            source: source,
            allowSDRFallback: true,
            itemPrefersDolbyVision: false,
            strictQualityMode: false,
            videoCodec: "hevc",
            allowAudioStreamCopy: false
        )

        XCTAssertTrue(shouldFallback)
    }

    func testPreemptiveH264FallbackStillTriggersForTenBitSDRSource() {
        let source = MediaSource(
            id: "source-sdr-10bit",
            itemID: "item-sdr-10bit",
            name: "SDR 10-bit Source",
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "eac3",
            videoBitDepth: 10,
            videoRange: "SDR",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: URL(string: "https://example.com/master.m3u8")
        )

        let shouldFallback = PlaybackSessionController.shouldPreferForceH264Fallback(
            transport: "fMP4",
            hasInitMap: false,
            source: source,
            allowSDRFallback: true,
            itemPrefersDolbyVision: false,
            strictQualityMode: false,
            videoCodec: "hevc",
            allowAudioStreamCopy: false
        )

        XCTAssertTrue(shouldFallback)
    }

    func testPreemptiveH264FallbackSkipsDolbyVisionOrStrictQuality() {
        let source = MediaSource(
            id: "source-dv",
            itemID: "item-dv",
            name: "DV Source",
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "eac3",
            videoRange: "DolbyVision",
            dvProfile: 8,
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: URL(string: "https://example.com/master.m3u8")
        )

        XCTAssertFalse(
            PlaybackSessionController.shouldPreferForceH264Fallback(
                transport: "fMP4",
                hasInitMap: false,
                source: source,
                allowSDRFallback: true,
                itemPrefersDolbyVision: true,
                strictQualityMode: false,
                videoCodec: "hevc",
                allowAudioStreamCopy: false
            )
        )

        XCTAssertFalse(
            PlaybackSessionController.shouldPreferForceH264Fallback(
                transport: "fMP4",
                hasInitMap: false,
                source: source,
                allowSDRFallback: true,
                itemPrefersDolbyVision: false,
                strictQualityMode: true,
                videoCodec: "hevc",
                allowAudioStreamCopy: false
            )
        )
    }

    func testDuplicateAttemptTripleIsSkipped() {
        var attempted = Set<String>()
        let key = PlaybackSessionController.attemptTripleKey(
            profile: .serverDefault,
            routeLabel: "Transcode (HLS)",
            url: "https://example.com/master.m3u8?variant=4k"
        )

        XCTAssertTrue(PlaybackSessionController.insertAttemptTriple(key, attempted: &attempted))
        XCTAssertFalse(PlaybackSessionController.insertAttemptTriple(key, attempted: &attempted))
    }

    func testPremiumDVContentUsesServerTranscodeInNativeMode() async throws {
        let configuration = ServerConfiguration(
            serverURL: URL(string: "https://example.com")!,
            playbackPolicy: .originalFirst,
            allowSDRFallback: true,
            preferAudioTranscodeOnly: true
        )

        let source = MediaSource(
            id: "src-1",
            itemID: "item-1",
            name: "Premium",
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 32_000_000,
            videoBitDepth: 10,
            videoRange: "DolbyVision",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: URL(string: "https://example.com/videos/item-1/master.m3u8?AllowVideoStreamCopy=true&AllowAudioStreamCopy=false&VideoCodec=hevc&Container=fmp4&SegmentContainer=fmp4")!
        )

        let api = CapturePlaybackAPIClient(configuration: configuration, sources: ["item-1": [source]])
        let coordinator = PlaybackCoordinator(apiClient: api)
        let selection = try await coordinator.resolvePlayback(itemID: "item-1", mode: .balanced, transcodeProfile: .serverDefault)

        XCTAssertEqual(selection.source.id, "src-1")
        // Native AVPlayer mode should avoid local bridge by default and use server path.
        XCTAssertEqual(selection.decision.playMethod, "Transcode")
    }

    func testPlaybackInfoRequestUsesVideoCopyInOriginalLock() async throws {
        let configuration = ServerConfiguration(
            serverURL: URL(string: "https://example.com")!,
            playbackPolicy: .originalLockHDRDV,
            allowSDRFallback: false,
            preferAudioTranscodeOnly: true
        )

        let source = MediaSource(
            id: "src-2",
            itemID: "item-2",
            name: "Premium",
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "eac3",
            bitrate: 28_000_000,
            videoBitDepth: 10,
            videoRange: "HDR10",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: URL(string: "https://example.com/videos/item-2/master.m3u8?Container=fmp4&SegmentContainer=fmp4&VideoCodec=hevc&AllowVideoStreamCopy=true")!
        )

        let api = CapturePlaybackAPIClient(configuration: configuration, sources: ["item-2": [source]])
        let coordinator = PlaybackCoordinator(apiClient: api)
        _ = try await coordinator.resolvePlayback(itemID: "item-2", mode: .balanced, transcodeProfile: .serverDefault)

        XCTAssertEqual(api.lastOptions?.allowVideoStreamCopy, true)
    }

    private func lowercasedQueryMap(from url: URL) -> [String: String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
            guard let value = item.value else { return nil }
            return (item.name.lowercased(), value.lowercased())
        })
    }

    func testDVProfile8WithDVBoxesInfersDolbyVision() throws {
        let track = makeHEVCTrack()
        var initSegment = Data()
        initSegment.append(MP4BoxWriter.writeFtyp(hasDolbyVision: true))
        initSegment.append(
            MP4BoxWriter.writeMoov(
                tracks: [track],
                duration: 90_000,
                timescale: 90_000,
                dvConfig: MP4BoxWriter.DVConfig(profile: 8, level: 6, compatibilityId: 1)
            )
        )

        let inspection = InitSegmentInspector.inspect(initSegment)
        XCTAssertTrue(inspection.hasHvcC)
        XCTAssertTrue(inspection.hasDvcC || inspection.hasDvvC)
        XCTAssertEqual(inspection.inferredMode, .dolbyVision)
    }

    func testDVSourceWithoutDVBoxesFallsBackToHDR10() throws {
        let track = makeHEVCTrack()
        var initSegment = Data()
        initSegment.append(MP4BoxWriter.writeFtyp(hasDolbyVision: false))
        initSegment.append(
            MP4BoxWriter.writeMoov(
                tracks: [track],
                duration: 90_000,
                timescale: 90_000,
                dvConfig: nil
            )
        )

        let inspection = InitSegmentInspector.inspect(initSegment)
        XCTAssertTrue(inspection.hasHvcC)
        XCTAssertFalse(inspection.hasDvcC || inspection.hasDvvC)
        XCTAssertEqual(inspection.inferredMode, .hdr10)
    }

    func testStrictPolicyRejectsSDRVariantForDVSource() {
        let source = MediaSource(
            id: "source-dv",
            itemID: "item",
            name: "DV Source",
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "eac3",
            videoBitDepth: 10,
            videoRange: "DolbyVision",
            dvProfile: 8,
            supportsDirectPlay: false,
            supportsDirectStream: true,
            directStreamURL: URL(string: "https://example.com/master.m3u8"),
            directPlayURL: nil,
            transcodeURL: URL(string: "https://example.com/master.m3u8")
        )
        let variant = HLSVariantInfo(
            streamInfLine: "BANDWIDTH=1000000,VIDEO-RANGE=SDR,CODECS=\"avc1.4d402a,mp4a.40.2\"",
            uriLine: "main.m3u8",
            resolvedURL: URL(string: "https://example.com/main.m3u8?Container=fmp4&SegmentContainer=fmp4&VideoCodec=h264")!,
            query: [
                "container": "fmp4",
                "segmentcontainer": "fmp4",
                "videocodec": "h264"
            ],
            codecs: "avc1.4d402a,mp4a.40.2",
            supplementalCodecs: "",
            videoRange: "SDR",
            bandwidth: 1_000_000,
            averageBandwidth: 1_000_000,
            frameRate: 23.976,
            width: 1920,
            height: 1080
        )

        let failure = HDRDVPolicy().validateStrictVariant(source: source, variant: variant)
        XCTAssertEqual(failure, .strictModeRejectedSDRVariant)
    }

    func testStrictSubtitlePolicyBlocksBitmapSubtitles() {
        let track = MediaTrack(
            id: "sub-1",
            title: "French PGS",
            language: "fr",
            codec: "pgs",
            isDefault: false,
            index: 1
        )

        XCTAssertTrue(
            SubtitleCompatibilityPolicy().shouldBlockSubtitleSelection(
                track: track,
                strictMode: true,
                sourceIsHDRorDV: true
            )
        )
    }

    func testAudioSelectorPrefersEAC3ForNativePath() {
        let tracks = [
            MediaTrack(id: "a1", title: "English TrueHD Atmos", language: "en", codec: "truehd", isDefault: true, index: 1),
            MediaTrack(id: "a2", title: "French E-AC-3 7.1", language: "fr", codec: "eac3", isDefault: false, index: 2)
        ]

        let selection = AudioCompatibilitySelector().selectPreferredAudioTrack(
            from: tracks,
            fallbackCodec: "truehd",
            nativePlayerPath: true
        )

        XCTAssertEqual(selection.selectedCodec, "eac3")
        XCTAssertEqual(selection.selectedTrackIndex, 2)
        XCTAssertTrue(selection.trueHDWasDeprioritized)
    }

    func testAssetURLValidatorRejectsUnsupportedScheme() {
        let validator = AssetURLValidator()
        XCTAssertNil(validator.validate(url: URL(string: "https://example.com/master.m3u8")!))
        XCTAssertNotNil(validator.validate(url: URL(string: "custom-scheme://example/master.m3u8")!))
    }

    func testDowngradeReasonForMissingDVBoxesIsExplicit() {
        let message = PlaybackFailureReason.missingDolbyVisionBoxesFallingBackToHDR10.localizedDescription ?? ""
        XCTAssertTrue(message.lowercased().contains("falling back"))
        XCTAssertTrue(message.lowercased().contains("hdr10"))
    }

    private func makeHEVCTrack() -> TrackInfo {
        TrackInfo(
            id: 1,
            trackType: .video,
            codecID: "V_MPEGH/ISO/HEVC",
            codecName: "hevc",
            isDefault: true,
            width: 3840,
            height: 1608,
            bitDepth: 10,
            codecPrivate: Data([
                0x01, 0x01, 0x60, 0x00, 0x00, 0x00, 0x90, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x99, 0xF0, 0x00, 0xFC,
                0xFD, 0xFA, 0xFA, 0x00, 0x00, 0x0F, 0x03, 0xA0
            ]),
            colourPrimaries: 9,
            transferCharacteristic: 16,
            matrixCoefficients: 9
        )
    }
}

private final class CapturePlaybackAPIClient: JellyfinAPIClientProtocol, @unchecked Sendable {
    private let configurationValue: ServerConfiguration
    private let sessionValue: UserSession
    private let sourcesByItem: [String: [MediaSource]]
    var lastOptions: PlaybackInfoOptions?

    init(configuration: ServerConfiguration, sources: [String: [MediaSource]]) {
        self.configurationValue = configuration
        self.sourcesByItem = sources
        self.sessionValue = UserSession(userID: "u1", username: "tester", token: "token")
    }

    func currentConfiguration() async -> ServerConfiguration? { configurationValue }
    func currentSession() async -> UserSession? { sessionValue }
    func configure(server: ServerConfiguration) async throws { _ = server }
    func testConnection(serverURL: URL) async throws { _ = serverURL }
    func authenticate(credentials: UserCredentials) async throws -> UserSession { _ = credentials; return sessionValue }
    func signOut() async {}
    func fetchUserViews() async throws -> [LibraryView] { [] }
    func fetchHomeFeed(since: Date?) async throws -> HomeFeed { _ = since; return .empty }
    func fetchItem(id: String) async throws -> MediaItem { throw AppError.network("Not implemented") }
    func fetchItemDetail(id: String) async throws -> MediaDetail { throw AppError.network("Not implemented") }
    func fetchSeasons(seriesID: String) async throws -> [MediaItem] { [] }
    func fetchEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] { [] }
    func fetchNextUpEpisode(seriesID: String) async throws -> MediaItem? { nil }
    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] { _ = query; return [] }
    func fetchPlaybackSources(itemID: String) async throws -> [MediaSource] { sourcesByItem[itemID] ?? [] }
    func fetchPlaybackSources(itemID: String, options: PlaybackInfoOptions) async throws -> [MediaSource] {
        lastOptions = options
        return try await fetchPlaybackSources(itemID: itemID)
    }
    func imageURL(for itemID: String, type: JellyfinImageType, width: Int?, quality: Int?) async -> URL? { nil }
    func reportPlayback(progress: PlaybackProgressUpdate) async throws { _ = progress }
    func reportPlayed(itemID: String) async throws { _ = itemID }
}
