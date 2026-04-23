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

    func testTvOSSimulatorCompatibilityPlaybackOptionsPreferH264Startup() {
        let options = PlaybackInfoOptions.tvOSSimulatorCompatibility(maxStreamingBitrate: 40_000_000)

        XCTAssertEqual(options.mode, .balanced)
        XCTAssertTrue(options.enableDirectPlay)
        XCTAssertFalse(options.enableDirectStream)
        XCTAssertTrue(options.allowTranscoding)
        XCTAssertEqual(options.maxStreamingBitrate, 12_000_000)
        XCTAssertEqual(options.allowVideoStreamCopy, false)
        XCTAssertEqual(options.allowAudioStreamCopy, false)
        XCTAssertEqual(options.maxAudioChannels, 2)
        XCTAssertEqual(options.deviceProfile, .tvOSSimulatorCompatibilityH264)
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

    func testImmediateH264RecoveryIsPreferredAfterServerDefaultDecodeFailure() {
        XCTAssertTrue(
            PlaybackSessionController.shouldPreferImmediateH264Recovery(
                activeProfile: .serverDefault,
                allowSDRFallback: true
            )
        )
    }

    func testImmediateH264RecoveryRespectsSDRFallbackPolicy() {
        XCTAssertFalse(
            PlaybackSessionController.shouldPreferImmediateH264Recovery(
                activeProfile: .serverDefault,
                allowSDRFallback: false
            )
        )
    }

    func testImmediateH264RecoveryDoesNotApplyAfterConservativeAttempt() {
        XCTAssertFalse(
            PlaybackSessionController.shouldPreferImmediateH264Recovery(
                activeProfile: .conservativeCompatibility,
                allowSDRFallback: true
            )
        )
    }

    func testStartupRecoveryDisablesDirectRoutesForUnsafeProgressiveFailures() {
        XCTAssertTrue(
            PlaybackSessionController.shouldDisableDirectRoutesForRecovery(
                reason: StartupFailureReason.startupReadinessTimeout.rawValue
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.shouldDisableDirectRoutesForRecovery(
                reason: StartupFailureReason.startupVideoPrerollTimeout.rawValue
            )
        )
        XCTAssertTrue(
            PlaybackSessionController.shouldDisableDirectRoutesForRecovery(
                reason: StartupFailureReason.directPlayPreflightInsufficient.rawValue
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldDisableDirectRoutesForRecovery(
                reason: StartupFailureReason.directPlayStall.rawValue
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldDisableDirectRoutesForRecovery(
                reason: StartupFailureReason.playerItemFailed.rawValue
            )
        )
    }

    func testDirectPlayRecoveryPreservesDirectPlayRoute() {
        XCTAssertTrue(
            PlaybackSessionController.shouldPreserveDirectPlayRecovery(
                route: .directPlay(URL(string: "https://example.com/Videos/item/stream?static=true")!)
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldPreserveDirectPlayRecovery(
                route: .transcode(URL(string: "https://example.com/videos/item/master.m3u8")!)
            )
        )
        XCTAssertFalse(
            PlaybackSessionController.shouldPreserveDirectPlayRecovery(route: nil)
        )
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

    func testPinnedHLSVariantPreservesMasterResumeQuery() throws {
        let masterURL = URL(string: "https://example.com/videos/item/master.m3u8?MediaSourceId=source&StartTimeTicks=51130000000&api_key=token")!
        let variantURL = URL(string: "https://example.com/videos/item/main.m3u8?MediaSourceId=source&api_key=token")!

        let resolved = PlaybackSessionController.variantURLPreservingResumeQuery(
            masterURL: masterURL,
            variantURL: variantURL
        )

        let query = Dictionary(
            uniqueKeysWithValues: URLComponents(url: resolved, resolvingAgainstBaseURL: false)!.queryItems!.map {
                ($0.name.lowercased(), $0.value ?? "")
            }
        )
        XCTAssertEqual(query["starttimeticks"], "51130000000")
        XCTAssertEqual(query["mediasourceid"], "source")
        XCTAssertEqual(query["api_key"], "token")
    }

    func testVariantPinningProfileKeepsExplicitConservativeRecoveryProfile() {
        let url = URL(
            string: "https://example.com/master.m3u8?AllowVideoStreamCopy=true&AllowAudioStreamCopy=false&VideoCodec=hevc&Container=fmp4&SegmentContainer=fmp4"
        )!

        let profile = PlaybackSessionController.variantPinningProfile(
            from: url,
            requestedProfile: .conservativeCompatibility
        )

        XCTAssertEqual(profile, .conservativeCompatibility)
    }

    func testVariantPinningProfilePromotesServerDefaultHEVCTranscode() {
        let url = URL(
            string: "https://example.com/master.m3u8?AllowVideoStreamCopy=false&AllowAudioStreamCopy=false&VideoCodec=hevc&Container=fmp4&SegmentContainer=fmp4"
        )!

        let profile = PlaybackSessionController.variantPinningProfile(
            from: url,
            requestedProfile: .serverDefault
        )

        XCTAssertEqual(profile, .appleOptimizedHEVC)
    }

    func testDegradedStartupVariantFlagsPinnedPlaceholderVariant() {
        XCTAssertTrue(
            PlaybackSessionController.isDegradedStartupVariant(
                width: 416,
                bandwidth: 640_000
            )
        )
    }

    func testDegradedStartupVariantAllowsHealthy4KStartupVariant() {
        XCTAssertFalse(
            PlaybackSessionController.isDegradedStartupVariant(
                width: 3_840,
                bandwidth: 12_000_000
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

        XCTAssertEqual(api.optionsHistory.first?.allowVideoStreamCopy, true)
        XCTAssertEqual(api.optionsHistory.last?.deviceProfile, .iosOptimizedHEVC)
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

    // MARK: - Audio Selection Tests

    func testAudioSelectorPenalizesTrueHDOnNativePath() {
        // TrueHD is not natively decodable by AVPlayer; even when marked default it
        // must lose to any natively-playable codec. This prevents black audio output.
        let tracks = [
            MediaTrack(id: "a1", title: "English TrueHD Atmos", language: "en", codec: "truehd", isDefault: true, index: 1),
            MediaTrack(id: "a2", title: "French E-AC-3 7.1", language: "fr", codec: "eac3", isDefault: false, index: 2),
        ]

        let selection = AudioCompatibilitySelector().selectPreferredAudioTrack(
            from: tracks,
            fallbackCodec: "truehd",
            nativePlayerPath: true
        )

        XCTAssertEqual(selection.selectedCodec, "eac3", "EAC3 must beat TrueHD default on native path")
        XCTAssertEqual(selection.selectedTrackIndex, 2)
        XCTAssertTrue(selection.trueHDWasDeprioritized)
    }

    func testAudioSelectorDefaultTrackBeatsHigherCodecWithNoLanguagePref() {
        // Without an explicit language preference, the `isDefault` flag (10 000 pts)
        // must outweigh codec prestige (400 pts for EAC3 vs 300 pts for AC3).
        // French AC3 marked default should beat English EAC3 non-default.
        let tracks = [
            MediaTrack(id: "a1", title: "English E-AC-3 Atmos", language: "en", codec: "eac3", isDefault: false, index: 1),
            MediaTrack(id: "a2", title: "French AC-3", language: "fr", codec: "ac3", isDefault: true, index: 2),
        ]

        let selection = AudioCompatibilitySelector().selectPreferredAudioTrack(
            from: tracks,
            fallbackCodec: "eac3",
            nativePlayerPath: true
        )

        XCTAssertEqual(selection.selectedCodec, "ac3", "Default AC3 must beat non-default EAC3")
        XCTAssertEqual(selection.selectedTrackIndex, 2)
        XCTAssertFalse(selection.trueHDWasDeprioritized)
    }

    func testAudioSelectorLanguageMatchBeatsDefault() {
        // Preferred language match (+100 000) must beat default bonus (+10 000).
        // Even if French track is not marked default, it wins when user prefers French.
        let tracks = [
            MediaTrack(id: "a1", title: "English EAC3 Atmos", language: "en", codec: "eac3", isDefault: true, index: 1),
            MediaTrack(id: "a2", title: "French AC3", language: "fr", codec: "ac3", isDefault: false, index: 2),
        ]

        let selection = AudioCompatibilitySelector().selectPreferredAudioTrack(
            from: tracks,
            fallbackCodec: "eac3",
            nativePlayerPath: true,
            preferredLanguage: "fr"
        )

        XCTAssertEqual(selection.selectedCodec, "ac3", "Preferred-language French AC3 must beat default English EAC3")
        XCTAssertEqual(selection.selectedTrackIndex, 2)
    }

    func testAudioSelectorHardCase_FrenchAC3DefaultBeatsEnglishEAC3Atmos_WithLanguagePref() {
        // THE hard case from MEGA PROMPT:
        // MKV / HEVC Main10 / DV 8.1 with:
        //   - Track 1: French AC-3 (default)
        //   - Track 2: English E-AC-3 Atmos (non-default)
        // User preferred language: French → French AC3 must win.
        let tracks = [
            MediaTrack(id: "a1", title: "Français AC-3", language: "fr", codec: "ac3", isDefault: true, index: 1),
            MediaTrack(id: "a2", title: "English E-AC-3 Atmos", language: "en", codec: "eac3", isDefault: false, index: 2),
        ]

        let selection = AudioCompatibilitySelector().selectPreferredAudioTrack(
            from: tracks,
            fallbackCodec: "eac3",
            nativePlayerPath: true,
            preferredLanguage: "fr"
        )

        XCTAssertEqual(selection.selectedCodec, "ac3")
        XCTAssertEqual(selection.selectedTrackIndex, 1)
    }

    func testAudioSelectorHardCase_FrenchAC3DefaultBeatsEnglishEAC3Atmos_NoLanguagePref() {
        // Same hard case, no language pref set.
        // Default bonus (10 000) must outweigh codec gap (100 pts).
        // French AC3 default must still win.
        let tracks = [
            MediaTrack(id: "a1", title: "Français AC-3", language: "fr", codec: "ac3", isDefault: true, index: 1),
            MediaTrack(id: "a2", title: "English E-AC-3 Atmos", language: "en", codec: "eac3", isDefault: false, index: 2),
        ]

        let selection = AudioCompatibilitySelector().selectPreferredAudioTrack(
            from: tracks,
            fallbackCodec: "eac3",
            nativePlayerPath: true,
            preferredLanguage: nil
        )

        XCTAssertEqual(selection.selectedCodec, "ac3", "Default track must win with no language preference")
        XCTAssertEqual(selection.selectedTrackIndex, 1)
    }

    func testAudioSelectorLanguageNormalizationISO6392() {
        // ISO 639-2 three-letter codes ("fre", "fra", "eng") must be treated the
        // same as ISO 639-1 two-letter codes ("fr", "en") when matching a preference.
        let tracks = [
            MediaTrack(id: "a1", title: "English AC-3", language: "eng", codec: "ac3", isDefault: false, index: 1),
            MediaTrack(id: "a2", title: "French EAC3", language: "fre", codec: "eac3", isDefault: false, index: 2),
        ]

        let selection = AudioCompatibilitySelector().selectPreferredAudioTrack(
            from: tracks,
            fallbackCodec: "ac3",
            nativePlayerPath: true,
            preferredLanguage: "fr"    // two-letter preference must match three-letter tag "fre"
        )

        XCTAssertEqual(selection.selectedCodec, "eac3", "ISO 639-2 'fre' must match ISO 639-1 'fr' preference")
        XCTAssertEqual(selection.selectedTrackIndex, 2)
    }

    func testAudioSelectorLanguageNormalizerRoundTrips() {
        // Smoke test for the normalizer to make sure common tags collapse correctly.
        XCTAssertEqual(AudioTrackLanguageNormalizer.normalize("fre"), "fr")
        XCTAssertEqual(AudioTrackLanguageNormalizer.normalize("fra"), "fr")
        XCTAssertEqual(AudioTrackLanguageNormalizer.normalize("fr-FR"), "fr")
        XCTAssertEqual(AudioTrackLanguageNormalizer.normalize("fr-CA"), "fr")
        XCTAssertEqual(AudioTrackLanguageNormalizer.normalize("eng"), "en")
        XCTAssertEqual(AudioTrackLanguageNormalizer.normalize("en-US"), "en")
        XCTAssertEqual(AudioTrackLanguageNormalizer.normalize("deu"), "de")
        XCTAssertEqual(AudioTrackLanguageNormalizer.normalize("ger"), "de")
        XCTAssertEqual(AudioTrackLanguageNormalizer.normalize("jpn"), "ja")
        XCTAssertEqual(AudioTrackLanguageNormalizer.normalize("zho"), "zh")
        XCTAssertTrue(AudioTrackLanguageNormalizer.matches("fre", "fr"))
        XCTAssertTrue(AudioTrackLanguageNormalizer.matches("fr-CA", "fr"))
        XCTAssertFalse(AudioTrackLanguageNormalizer.matches("fre", "en"))
    }

    func testAudioSelectorFallsBackToFirstTrackWhenNoMatch() {
        // When no track matches any preference tier, the first track (stream order 0)
        // should win as the tie-breaker.
        let tracks = [
            MediaTrack(id: "a1", title: "AAC Stereo", language: "und", codec: "aac", isDefault: false, index: 1),
            MediaTrack(id: "a2", title: "AAC Stereo", language: "und", codec: "aac", isDefault: false, index: 2),
        ]

        let selection = AudioCompatibilitySelector().selectPreferredAudioTrack(
            from: tracks,
            fallbackCodec: "aac",
            nativePlayerPath: true,
            preferredLanguage: "fr"    // no French track — falls through to stream order
        )

        // Either track is acceptable, but index 1 (stream order 0) must be preferred
        XCTAssertEqual(selection.selectedTrackIndex, 1)
    }

    func testAudioSelectorPrefersEAC3ForNativePath() {
        // Legacy name kept for back-compat.  Now validated by testAudioSelectorPenalizesTrueHDOnNativePath.
        let tracks = [
            MediaTrack(id: "a1", title: "English TrueHD Atmos", language: "en", codec: "truehd", isDefault: true, index: 1),
            MediaTrack(id: "a2", title: "French E-AC-3 7.1", language: "fr", codec: "eac3", isDefault: false, index: 2),
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

    // MARK: - StartupFailureReason Tests

    func testStartupFailureReasonReadyButNoVideoFrameTriggersRecovery() {
        XCTAssertTrue(StartupFailureReason.readyButNoVideoFrame.shouldTriggerRecovery)
    }

    func testStartupFailureReasonDecoderStallTriggersRecovery() {
        XCTAssertTrue(StartupFailureReason.decoderStall.shouldTriggerRecovery)
    }

    func testStartupFailureReasonDecodedFrameWatchdogTriggersRecovery() {
        XCTAssertTrue(StartupFailureReason.decodedFrameWatchdog.shouldTriggerRecovery)
    }

    func testStartupFailureReasonDirectPlayStartupGuardsTriggerRecovery() {
        XCTAssertTrue(StartupFailureReason.startupReadinessTimeout.shouldTriggerRecovery)
        XCTAssertTrue(StartupFailureReason.startupVideoPrerollTimeout.shouldTriggerRecovery)
        XCTAssertFalse(StartupFailureReason.directPlayPreflightInsufficient.shouldTriggerRecovery)
        XCTAssertFalse(StartupFailureReason.directPlayStall.shouldTriggerRecovery)
    }

    func testStartupFailureReasonTransientDoesNotTriggerRecovery() {
        XCTAssertFalse(StartupFailureReason.playerItemFailedTransient.shouldTriggerRecovery)
    }

    func testStartupFailureReasonNativeBridgeDoesNotTriggerRecovery() {
        XCTAssertFalse(StartupFailureReason.nativeBridgePackagingFailure.shouldTriggerRecovery)
    }

    func testStartupFailureReasonRawValueRoundTrip() {
        for reason in [
            StartupFailureReason.manifestLoadFailed,
            .firstSegmentTimeout,
            .decodedFrameWatchdog,
            .readyButNoVideoFrame,
            .decoderStall,
            .presentationSizeZero,
            .playerItemFailed,
            .startupReadinessTimeout,
            .startupVideoPrerollTimeout,
            .directPlayPreflightInsufficient,
            .directPlayStall,
            .startupWatchdogExpired,
            .nativeBridgePackagingFailure,
            .unknownStartupFailure
        ] {
            XCTAssertEqual(StartupFailureReason(rawValue: reason.rawValue), reason)
        }
    }

    // MARK: - Recovery Ordering Tests

    func testRecoveryAfterForceH264HasNoFurtherFallback() {
        let profiles = PlaybackSessionController.recoveryPlan(
            after: .forceH264Transcode,
            policy: .auto,
            allowSDRFallback: true
        )
        XCTAssertTrue(profiles.isEmpty)
    }

    func testStartupRecoveryCandidateStopsAtTerminalFallbackProfile() {
        let hasCandidate = PlaybackSessionController.hasStartupRecoveryCandidate(
            after: .forceH264Transcode,
            playbackPolicy: .auto,
            allowSDRFallback: true,
            usesDirectRemuxOnly: false
        )

        XCTAssertFalse(hasCandidate)
    }

    func testStartupRecoveryCandidateAllowsInitialFallbackProfiles() {
        let hasCandidate = PlaybackSessionController.hasStartupRecoveryCandidate(
            after: .serverDefault,
            playbackPolicy: .auto,
            allowSDRFallback: true,
            usesDirectRemuxOnly: false
        )

        XCTAssertTrue(hasCandidate)
    }

    func testStartupRecoveryCandidateKeepsDirectRemuxOnlyRecoveryPath() {
        let hasCandidate = PlaybackSessionController.hasStartupRecoveryCandidate(
            after: .forceH264Transcode,
            playbackPolicy: .auto,
            allowSDRFallback: true,
            usesDirectRemuxOnly: true
        )

        XCTAssertTrue(hasCandidate)
    }

    func testFallbackOrderIsDeterministic() {
        let p1 = PlaybackSessionController.recoveryPlan(after: .serverDefault, policy: .auto, allowSDRFallback: true)
        let p2 = PlaybackSessionController.recoveryPlan(after: .serverDefault, policy: .auto, allowSDRFallback: true)
        XCTAssertEqual(p1, p2)
    }

    func testFallbackOrderNeverRepeatsActiveProfile() {
        for active in [TranscodeURLProfile.serverDefault, .appleOptimizedHEVC, .conservativeCompatibility, .forceH264Transcode] {
            let profiles = PlaybackSessionController.recoveryPlan(after: active, policy: .auto, allowSDRFallback: true)
            XCTAssertFalse(profiles.contains(active))
        }
    }

    func testNoSyntheticDirectPlayURLForMKVWithoutExplicitURL() {
        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "no-urls",
                itemID: "item",
                name: "No URLs",
                container: "mkv",
                videoCodec: "hevc",
                audioCodec: "eac3",
                supportsDirectPlay: false,
                supportsDirectStream: false,
                directStreamURL: nil,
                directPlayURL: nil,
                transcodeURL: URL(string: "https://example.com/master.m3u8")
            )
        ]
        let decision = engine.decide(
            itemID: "item",
            sources: sources,
            configuration: ServerConfiguration(serverURL: URL(string: "https://example.com")!),
            token: "abc"
        )
        if let decision {
            if case .directPlay = decision.route {
                XCTFail("Should not synthesize directPlay URL for MKV without explicit server URL")
            }
        }
    }

    // MARK: - ServerConfiguration language fields

    func testServerConfigurationPreferredLanguageRoundTrips() throws {
        let config = ServerConfiguration(
            serverURL: URL(string: "https://example.com")!,
            preferredAudioLanguage: "fr",
            preferredSubtitleLanguage: "en"
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ServerConfiguration.self, from: data)

        XCTAssertEqual(decoded.preferredAudioLanguage, "fr")
        XCTAssertEqual(decoded.preferredSubtitleLanguage, "en")
    }

    func testServerConfigurationDefaultsToNilLanguages() {
        let config = ServerConfiguration(serverURL: URL(string: "https://example.com")!)
        XCTAssertNil(config.preferredAudioLanguage)
        XCTAssertNil(config.preferredSubtitleLanguage)
    }

    // MARK: - Playback decision with preferred language

    func testPlaybackCoordinatorPassesPreferredLanguageToAudioSelection() async throws {
        // When the server configuration carries a preferred audio language,
        // the coordinator must respect it when selecting the AudioStreamIndex.
        let configuration = ServerConfiguration(
            serverURL: URL(string: "https://example.com")!,
            playbackPolicy: .auto,
            allowSDRFallback: true,
            preferAudioTranscodeOnly: false,
            preferredAudioLanguage: "fr"
        )

        let frTrack = MediaTrack(id: "t-fr", title: "Français AC-3", language: "fr", codec: "ac3", isDefault: true, index: 1)
        let enTrack = MediaTrack(id: "t-en", title: "English EAC3 Atmos", language: "en", codec: "eac3", isDefault: false, index: 2)

        let source = MediaSource(
            id: "src-lang",
            itemID: "item-lang",
            name: "Lang Test",
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "ac3",
            bitrate: 15_000_000,
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: URL(string: "https://example.com/videos/item-lang/master.m3u8?Container=fmp4&VideoCodec=hevc")!,
            audioTracks: [frTrack, enTrack]
        )

        let api = CapturePlaybackAPIClient(configuration: configuration, sources: ["item-lang": [source]])
        let coordinator = PlaybackCoordinator(apiClient: api)
        let selection = try await coordinator.resolvePlayback(itemID: "item-lang", mode: .balanced)

        // AudioStreamIndex should point to the French track (index 1), not the English one.
        let url = selection.assetURL.absoluteString
        XCTAssertTrue(
            url.contains("AudioStreamIndex=1"),
            "Expected AudioStreamIndex=1 (French AC3) in URL, got: \(url)"
        )
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
    var optionsHistory: [PlaybackInfoOptions] = []

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
    func initiateQuickConnect(serverURL: URL) async throws -> QuickConnectState { throw AppError.unknown }
    func pollQuickConnect(secret: String) async throws -> UserSession? { nil }
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
        optionsHistory.append(options)
        return try await fetchPlaybackSources(itemID: itemID)
    }
    func imageURL(for itemID: String, type: JellyfinImageType, width: Int?, quality: Int?) async -> URL? { nil }
    func reportPlayback(progress: PlaybackProgressUpdate) async throws { _ = progress }
    func reportPlayed(itemID: String) async throws { _ = itemID }
}
