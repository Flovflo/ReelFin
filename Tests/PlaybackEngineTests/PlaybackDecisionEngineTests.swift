import PlaybackEngine
import Shared
import XCTest

final class PlaybackDecisionEngineTests: XCTestCase {
    private let server = ServerConfiguration(serverURL: URL(string: "https://example.com")!)

    func testDirectPlayPreferredWhenCompatible() {
        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "direct",
                itemID: "item",
                name: "Direct",
                container: "mp4",
                videoCodec: "h264",
                audioCodec: "aac",
                supportsDirectPlay: true,
                supportsDirectStream: true,
                directStreamURL: URL(string: "https://example.com/direct-stream.mp4"),
                directPlayURL: URL(string: "https://example.com/direct-play.mp4"),
                transcodeURL: URL(string: "https://example.com/transcode.m3u8")
            )
        ]

        let decision = engine.decide(itemID: "item", sources: sources, configuration: server, token: "abc")

        XCTAssertEqual(decision?.sourceID, "direct")
        XCTAssertEqual(decision?.route, .directPlay(URL(string: "https://example.com/direct-play.mp4")!))
    }

    func testDirectPlayPreferredWhenContainerIsCommaSeparatedList() {
        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "direct-csv",
                itemID: "item",
                name: "Direct CSV",
                container: "mov,mp4,m4a,3gp,3g2,mj2",
                videoCodec: "hevc",
                audioCodec: "eac3",
                supportsDirectPlay: true,
                supportsDirectStream: true,
                directStreamURL: URL(string: "https://example.com/direct-stream.mp4"),
                directPlayURL: URL(string: "https://example.com/direct-play.mp4"),
                transcodeURL: URL(string: "https://example.com/transcode.m3u8")
            )
        ]

        let decision = engine.decide(itemID: "item", sources: sources, configuration: server, token: "abc")

        XCTAssertEqual(decision?.sourceID, "direct-csv")
        XCTAssertEqual(decision?.route, .directPlay(URL(string: "https://example.com/direct-play.mp4")!))
    }

    func testDirectPlayPreferredWhenSourceCodecUnsupportedButAACTrackExists() {
        let engine = PlaybackDecisionEngine(
            capabilities: DeviceCapabilities(
                directPlayableContainers: ["mp4", "mov", "m4v"],
                videoCodecs: ["hevc", "h264", "avc1"],
                audioCodecs: ["aac"]
            )
        )
        let sources = [
            MediaSource(
                id: "direct-aac",
                itemID: "item",
                name: "Direct AAC",
                container: "mp4",
                videoCodec: "hevc",
                audioCodec: "eac3",
                supportsDirectPlay: true,
                supportsDirectStream: true,
                directStreamURL: URL(string: "https://example.com/direct-stream.mp4"),
                directPlayURL: URL(string: "https://example.com/direct-play.mp4"),
                transcodeURL: URL(string: "https://example.com/transcode.m3u8"),
                audioTracks: [
                    MediaTrack(id: "t1", title: "FR E-AC3", language: "fra", codec: "eac3", isDefault: true, index: 1),
                    MediaTrack(id: "t2", title: "FR AAC", language: "fra", codec: "aac", isDefault: false, index: 2)
                ]
            )
        ]

        let decision = engine.decide(itemID: "item", sources: sources, configuration: server, token: "abc")

        XCTAssertEqual(decision?.sourceID, "direct-aac")
        XCTAssertEqual(decision?.route, .directPlay(URL(string: "https://example.com/direct-play.mp4")!))
    }

    func testForcesRawDirectPlayWhenNoDirectURLsButContainerIsAppleCompatible() {
        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "raw-forced",
                itemID: "item",
                name: "Raw forced",
                container: "mov,mp4,m4a,3gp,3g2,mj2",
                videoCodec: "hevc",
                audioCodec: "aac",
                supportsDirectPlay: false,
                supportsDirectStream: false,
                directStreamURL: nil,
                directPlayURL: nil,
                transcodeURL: URL(string: "https://example.com/transcode.m3u8")
            )
        ]

        let decision = engine.decide(itemID: "item", sources: sources, configuration: server, token: "abc")

        XCTAssertEqual(
            decision?.route,
            .directPlay(URL(string: "https://example.com/Videos/item/stream?static=true&mediaSourceId=raw-forced&api_key=abc")!)
        )
    }

    func testAudioSelectorDefaultTrackBeatsHigherNativeCodecWithSameLanguage() {
        // EAC3 is the default track and AAC is non-default, both French.
        // Default-track bonus (+10 000) far exceeds codec delta (AAC +500 vs EAC3 +400),
        // so EAC3-default wins even though AAC has a slightly higher native codec score.
        let selector = AudioCompatibilitySelector()
        let tracks = [
            MediaTrack(id: "1", title: "French E-AC3", language: "fra", codec: "eac3", isDefault: true, index: 1),
            MediaTrack(id: "2", title: "French AAC", language: "fra", codec: "aac", isDefault: false, index: 2)
        ]

        let selection = selector.selectPreferredAudioTrack(
            from: tracks,
            fallbackCodec: "eac3",
            nativePlayerPath: true
        )

        XCTAssertEqual(selection.selectedCodec, "eac3")
        XCTAssertEqual(selection.selectedTrackIndex, 1)
    }

    func testRemuxUsedWhenDirectPlayNotCompatible() {
        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "remux",
                itemID: "item",
                name: "Remux",
                container: "mkv",
                videoCodec: "hevc",
                audioCodec: "aac",
                supportsDirectPlay: false,
                supportsDirectStream: true,
                directStreamURL: URL(string: "https://example.com/remux/master.m3u8"),
                directPlayURL: nil,
                transcodeURL: URL(string: "https://example.com/transcode.m3u8")
            )
        ]

        let decision = engine.decide(itemID: "item", sources: sources, configuration: server, token: "abc")

        XCTAssertEqual(decision?.sourceID, "remux")
        XCTAssertEqual(decision?.route, .transcode(URL(string: "https://example.com/transcode.m3u8")!))
    }

    func testNativeBridgeDisabledDefaultsToServerRoute() {
        let expiry = Date().timeIntervalSince1970 + 600
        UserDefaults.standard.set(["item-bad": expiry], forKey: "reelfin.nativebridge.disabled.items")
        defer { UserDefaults.standard.removeObject(forKey: "reelfin.nativebridge.disabled.items") }

        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "mkv-source",
                itemID: "item-bad",
                name: "MKV",
                container: "mkv",
                videoCodec: "hevc",
                audioCodec: "aac",
                supportsDirectPlay: false,
                supportsDirectStream: true,
                directStreamURL: URL(string: "https://example.com/remux/master.m3u8"),
                directPlayURL: nil,
                transcodeURL: URL(string: "https://example.com/transcode.m3u8")
            )
        ]

        let decision = engine.decide(itemID: "item-bad", sources: sources, configuration: server, token: "abc")
        XCTAssertEqual(decision?.route, .transcode(URL(string: "https://example.com/transcode.m3u8")!))
    }

    func testJitPlanKeepsDirectPlayForAppleContainers() {
        let plan = PlaybackPlan(
            itemID: "item-jit-mp4",
            sourceID: "source-jit-mp4",
            lane: .jitRepackageHLS,
            targetURL: URL(string: "https://example.com/transcode.m3u8"),
            selectedVideoCodec: "hevc",
            selectedAudioCodec: "eac3",
            selectedSubtitleCodec: nil,
            hdrMode: .dolbyVision,
            subtitleMode: .native,
            seekMode: .serverManaged,
            fallbackGraph: [.audioTranscodeOnly, .fullTranscode],
            reasonChain: PlaybackReasonChain()
        )
        let engine = PlaybackDecisionEngine(
            capabilityEngine: FixedPlanCapabilityEngine(plan: plan),
            mediaProbe: PassthroughMediaProbe()
        )
        let source = MediaSource(
            id: "source-jit-mp4",
            itemID: "item-jit-mp4",
            name: "DV MP4",
            container: "mp4",
            videoCodec: "dvh1",
            audioCodec: "eac3",
            supportsDirectPlay: true,
            supportsDirectStream: true,
            directStreamURL: URL(string: "https://example.com/stream.m3u8"),
            directPlayURL: URL(string: "https://example.com/direct.mp4"),
            transcodeURL: URL(string: "https://example.com/transcode.m3u8")
        )

        let decision = engine.decide(
            itemID: "item-jit-mp4",
            sources: [source],
            configuration: server,
            token: "abc"
        )

        XCTAssertEqual(decision?.route, .directPlay(URL(string: "https://example.com/direct.mp4")!))
    }

    func testCoordinatorKeepsDirectPlayWhenSourceIsCompatible() async throws {
        let configuration = ServerConfiguration(
            serverURL: URL(string: "https://example.com")!,
            forceH264FallbackWhenNotDirectPlay: true
        )
        let session = UserSession(userID: "user", username: "tester", token: "abc")
        let source = MediaSource(
            id: "source-direct",
            itemID: "item-direct",
            name: "Direct MP4",
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            supportsDirectPlay: true,
            supportsDirectStream: true,
            directStreamURL: URL(string: "https://example.com/direct-stream.mp4"),
            directPlayURL: URL(string: "https://example.com/direct-play.mp4"),
            transcodeURL: URL(string: "https://example.com/master.m3u8")
        )
        let apiClient = PlaybackCoordinatorTestAPIClient(
            configuration: configuration,
            session: session,
            sourcesByItemID: ["item-direct": [source]]
        )
        let coordinator = PlaybackCoordinator(apiClient: apiClient)

        let selection = try await coordinator.resolvePlayback(
            itemID: "item-direct",
            mode: .balanced,
            allowTranscodingFallbackInPerformance: true,
            transcodeProfile: .serverDefault
        )

        guard case let .directPlay(url) = selection.decision.route else {
            return XCTFail("Expected direct play route for a compatible MP4 source")
        }

        XCTAssertEqual(url, URL(string: "https://example.com/direct-play.mp4"))
        XCTAssertTrue(selection.assetURL.absoluteString.contains("/Videos/item-direct/stream"))
        XCTAssertFalse(selection.assetURL.absoluteString.contains("master.m3u8"))
        XCTAssertEqual(selection.debugInfo.playMethod, "DirectPlay")
    }

    func testCoordinatorKeepsExternalDirectPlayURLForMockLikeSources() async throws {
        let configuration = ServerConfiguration(serverURL: URL(string: "https://demo.reelfin.app")!)
        let session = UserSession(userID: "user", username: "tester", token: "abc")
        let source = MediaSource(
            id: "source-external",
            itemID: "item-external",
            name: "External HLS",
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            supportsDirectPlay: true,
            supportsDirectStream: true,
            directStreamURL: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8"),
            directPlayURL: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8"),
            transcodeURL: URL(string: "https://demo.reelfin.app/Videos/item-external/master.m3u8")
        )
        let apiClient = PlaybackCoordinatorTestAPIClient(
            configuration: configuration,
            session: session,
            sourcesByItemID: ["item-external": [source]]
        )
        let coordinator = PlaybackCoordinator(apiClient: apiClient)

        let selection = try await coordinator.resolvePlayback(itemID: "item-external", mode: .balanced)

        XCTAssertEqual(selection.assetURL.host, "devstreaming-cdn.apple.com")
        XCTAssertEqual(selection.assetURL.path, "/videos/streaming/examples/adv_dv_atmos/main.m3u8")
        XCTAssertFalse(selection.assetURL.absoluteString.contains("demo.reelfin.app/Videos/item-external/stream"))
        XCTAssertEqual(selection.debugInfo.playMethod, "DirectPlay")
    }

    func testJitPlanForcesRawDirectPlayWhenAppleContainerIsCompatible() {
        let plan = PlaybackPlan(
            itemID: "item-jit-mov",
            sourceID: "source-jit-mov",
            lane: .jitRepackageHLS,
            targetURL: URL(string: "https://example.com/transcode.m3u8"),
            selectedVideoCodec: "hevc",
            selectedAudioCodec: "eac3",
            selectedSubtitleCodec: nil,
            hdrMode: .hdr10,
            subtitleMode: .native,
            seekMode: .serverManaged,
            fallbackGraph: [.audioTranscodeOnly, .fullTranscode],
            reasonChain: PlaybackReasonChain()
        )
        let engine = PlaybackDecisionEngine(
            capabilityEngine: FixedPlanCapabilityEngine(plan: plan),
            mediaProbe: PassthroughMediaProbe()
        )
        let source = MediaSource(
            id: "source-jit-mov",
            itemID: "item-jit-mov",
            name: "MOV source",
            container: "mov",
            videoCodec: "hevc",
            audioCodec: "aac",
            supportsDirectPlay: false,
            supportsDirectStream: true,
            directStreamURL: URL(string: "https://example.com/remux/master.m3u8"),
            directPlayURL: nil,
            transcodeURL: URL(string: "https://example.com/transcode.m3u8")
        )

        let decision = engine.decide(
            itemID: "item-jit-mov",
            sources: [source],
            configuration: server,
            token: "abc"
        )

        XCTAssertEqual(
            decision?.route,
            .directPlay(URL(string: "https://example.com/Videos/item-jit-mov/stream?static=true&mediaSourceId=source-jit-mov&api_key=abc")!)
        )
    }

    func testTranscodeFallbackWhenNoDirectOptions() {
        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "transcode",
                itemID: "item",
                name: "Transcode",
                container: "avi",
                videoCodec: "mpeg2",
                audioCodec: "dts",
                supportsDirectPlay: false,
                supportsDirectStream: false,
                directStreamURL: nil,
                directPlayURL: nil,
                transcodeURL: URL(string: "https://example.com/transcode.m3u8")
            )
        ]

        let decision = engine.decide(itemID: "item", sources: sources, configuration: server, token: "abc")

        XCTAssertEqual(decision?.sourceID, "transcode")
        XCTAssertEqual(decision?.route, .transcode(URL(string: "https://example.com/transcode.m3u8")!))
    }

    func testPerformanceModeCanRejectWhenOnlyTranscodeAvailable() {
        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "transcode-only",
                itemID: "item",
                name: "Only Transcode",
                container: "avi",
                videoCodec: "mpeg4",
                audioCodec: "dts",
                supportsDirectPlay: false,
                supportsDirectStream: false,
                directStreamURL: nil,
                directPlayURL: nil,
                transcodeURL: URL(string: "https://example.com/transcode.m3u8")
            )
        ]

        let decision = engine.decide(
            itemID: "item",
            sources: sources,
            configuration: server,
            token: "abc",
            allowTranscoding: false
        )

        XCTAssertNil(decision)
    }

    func testDolbyVisionDirectPlayWinsOverH264() {
        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "h264",
                itemID: "item",
                name: "h264",
                container: "mp4",
                videoCodec: "h264",
                audioCodec: "aac",
                supportsDirectPlay: true,
                supportsDirectStream: true,
                directStreamURL: URL(string: "https://example.com/h264.mp4"),
                directPlayURL: URL(string: "https://example.com/h264.mp4"),
                transcodeURL: URL(string: "https://example.com/transcode.m3u8")
            ),
            MediaSource(
                id: "dv",
                itemID: "item",
                name: "dv",
                container: "mp4",
                videoCodec: "dvh1",
                audioCodec: "eac3",
                videoBitDepth: 10,
                videoRange: "DolbyVision",
                audioChannelLayout: "7.1 Atmos",
                supportsDirectPlay: true,
                supportsDirectStream: true,
                directStreamURL: URL(string: "https://example.com/dv.mp4"),
                directPlayURL: URL(string: "https://example.com/dv.mp4"),
                transcodeURL: URL(string: "https://example.com/transcode.m3u8")
            )
        ]

        let decision = engine.decide(itemID: "item", sources: sources, configuration: server, token: "abc")

        XCTAssertEqual(decision?.sourceID, "dv")
        XCTAssertEqual(decision?.route, .directPlay(URL(string: "https://example.com/dv.mp4")!))
    }

    func testFallbackTranscodeURLKeepsVideoCopyAndPreferredAppleAudio() {
        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "fallback-hevc",
                itemID: "item",
                name: "fallback",
                container: "avi",
                videoCodec: "hevc",
                audioCodec: "eac3",
                supportsDirectPlay: false,
                supportsDirectStream: false,
                directStreamURL: nil,
                directPlayURL: nil,
                transcodeURL: nil
            )
        ]

        let decision = engine.decide(itemID: "item", sources: sources, configuration: server, token: "abc")

        guard case let .transcode(url) = decision?.route else {
            XCTFail("Expected transcode route")
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryMap: [String: String] = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })

        XCTAssertEqual(queryMap["VideoCodec"], "hevc")
        XCTAssertEqual(queryMap["AudioCodec"], "eac3")
        XCTAssertEqual(queryMap["AllowVideoStreamCopy"], "true")
        XCTAssertEqual(queryMap["AllowAudioStreamCopy"], "false")
        XCTAssertEqual(queryMap["Container"], "fmp4")
        XCTAssertEqual(queryMap["SegmentContainer"], "fmp4")
    }

    func testCoordinatorConservativeProfileKeepsVideoCopy() async throws {
        // Use preferAudioTranscodeOnly: false so the profile can exercise audio-copy path.
        let configWithAudioCopy = ServerConfiguration(
            serverURL: URL(string: "https://example.com")!,
            preferAudioTranscodeOnly: false
        )
        let source = MediaSource(
            id: "source-1",
            itemID: "item-1",
            name: "HEVC source",
            container: "avi",
            videoCodec: "hevc",
            audioCodec: "eac3",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: URL(string: "https://example.com/Videos/item-1/master.m3u8?MediaSourceId=source-1&VideoCodec=hevc")
        )
        let client = MockPlaybackAPIClient(configuration: configWithAudioCopy, sources: ["item-1": [source]])
        let coordinator = PlaybackCoordinator(apiClient: client)

        let selection = try await coordinator.resolvePlayback(
            itemID: "item-1",
            mode: .balanced,
            allowTranscodingFallbackInPerformance: true,
            transcodeProfile: .conservativeCompatibility
        )

        guard case .transcode = selection.decision.route else {
            XCTFail("Expected transcode route")
            return
        }

        let queryMap = queryMap(from: selection.assetURL)
        XCTAssertEqual(queryMap["VideoCodec"], "hevc")
        XCTAssertEqual(queryMap["AllowVideoStreamCopy"], "true")
        XCTAssertEqual(queryMap["AudioCodec"], "eac3")
        XCTAssertEqual(queryMap["AllowAudioStreamCopy"], "true")
        XCTAssertEqual(queryMap["Container"], "fmp4")
        XCTAssertEqual(queryMap["SegmentContainer"], "fmp4")
        XCTAssertEqual(queryMap["BreakOnNonKeyFrames"], "False")
    }

    func testCoordinatorAppleOptimizedProfileForcesHEVCTranscode() async throws {
        // Use preferAudioTranscodeOnly: false so the profile can exercise audio-copy path.
        let configWithAudioCopy = ServerConfiguration(
            serverURL: URL(string: "https://example.com")!,
            preferAudioTranscodeOnly: false
        )
        let source = MediaSource(
            id: "source-apple-hevc",
            itemID: "item-apple-hevc",
            name: "HEVC source",
            container: "avi",
            videoCodec: "hevc",
            audioCodec: "eac3",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: URL(string: "https://example.com/Videos/item-apple-hevc/master.m3u8?MediaSourceId=source-apple-hevc&VideoCodec=hevc")
        )
        let client = MockPlaybackAPIClient(configuration: configWithAudioCopy, sources: ["item-apple-hevc": [source]])
        let coordinator = PlaybackCoordinator(apiClient: client)

        let selection = try await coordinator.resolvePlayback(
            itemID: "item-apple-hevc",
            mode: .balanced,
            allowTranscodingFallbackInPerformance: true,
            transcodeProfile: .appleOptimizedHEVC
        )

        guard case .transcode = selection.decision.route else {
            XCTFail("Expected transcode route")
            return
        }

        let queryMap = queryMap(from: selection.assetURL)
        XCTAssertEqual(queryMap["VideoCodec"], "hevc")
        XCTAssertEqual(queryMap["AllowVideoStreamCopy"], "false")
        XCTAssertEqual(queryMap["AudioCodec"], "eac3")
        XCTAssertEqual(queryMap["AllowAudioStreamCopy"], "true")
        XCTAssertEqual(queryMap["Container"], "fmp4")
        XCTAssertEqual(queryMap["SegmentContainer"], "fmp4")
        XCTAssertEqual(queryMap["BreakOnNonKeyFrames"], "False")
    }

    func testCoordinatorServerDefaultKeepsHEVCStreamCopyOnFirstAttempt() async throws {
        let source = MediaSource(
            id: "source-server-default-hevc",
            itemID: "item-server-default-hevc",
            name: "HEVC source",
            container: "avi",
            videoCodec: "hevc",
            audioCodec: "eac3",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: URL(string: "https://example.com/Videos/item-server-default-hevc/master.m3u8?MediaSourceId=source-server-default-hevc&VideoCodec=hevc&AllowVideoStreamCopy=true&AllowAudioStreamCopy=false&Container=fmp4&SegmentContainer=fmp4")
        )
        let client = MockPlaybackAPIClient(configuration: server, sources: ["item-server-default-hevc": [source]])
        let coordinator = PlaybackCoordinator(apiClient: client)

        let selection = try await coordinator.resolvePlayback(
            itemID: "item-server-default-hevc",
            mode: .balanced,
            allowTranscodingFallbackInPerformance: true,
            transcodeProfile: .serverDefault
        )

        guard case .transcode = selection.decision.route else {
            XCTFail("Expected transcode route")
            return
        }

        let queryMap = queryMap(from: selection.assetURL)
        XCTAssertEqual(queryMap["VideoCodec"], "hevc")
        XCTAssertEqual(queryMap["AllowVideoStreamCopy"], "true")
        XCTAssertEqual(queryMap["AllowAudioStreamCopy"], "false")
        XCTAssertEqual(queryMap["Container"], "fmp4")
        XCTAssertEqual(queryMap["SegmentContainer"], "fmp4")
        // serverDefault + playbackPolicy.auto returns server URL as-is (no forced rewrite)
        XCTAssertNil(queryMap["BreakOnNonKeyFrames"])
    }

    func testCoordinatorConservativeProfileTranscodesAC3ToAACWhenAudioCopyIsDisabled() async throws {
        // Verifies that preferAudioTranscodeOnly: true forces AudioCodec→aac and
        // AllowAudioStreamCopy→false on the conservativeCompatibility profile.
        // (serverDefault intentionally bypasses URL normalization to trust Jellyfin's URL.)
        let configAudioTranscodeOnly = ServerConfiguration(
            serverURL: URL(string: "https://example.com")!,
            preferAudioTranscodeOnly: true
        )
        let source = MediaSource(
            id: "source-conservative-h264-ac3",
            itemID: "item-conservative-h264-ac3",
            name: "H264 AC3 source",
            container: "mkv",
            videoCodec: "h264",
            audioCodec: "ac3",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: URL(
                string: "https://example.com/Videos/item-conservative-h264-ac3/master.m3u8?MediaSourceId=source-conservative-h264-ac3&VideoCodec=h264&AllowVideoStreamCopy=true&Container=ts&SegmentContainer=ts"
            )
        )
        let client = MockPlaybackAPIClient(configuration: configAudioTranscodeOnly, sources: ["item-conservative-h264-ac3": [source]])
        let coordinator = PlaybackCoordinator(apiClient: client)

        let selection = try await coordinator.resolvePlayback(
            itemID: "item-conservative-h264-ac3",
            mode: .balanced,
            allowTranscodingFallbackInPerformance: true,
            transcodeProfile: .conservativeCompatibility
        )

        guard case .transcode = selection.decision.route else {
            XCTFail("Expected transcode route")
            return
        }

        let queryMap = queryMap(from: selection.assetURL)
        XCTAssertEqual(queryMap["VideoCodec"], "h264")
        XCTAssertEqual(queryMap["AllowVideoStreamCopy"], "true")
        XCTAssertEqual(queryMap["AllowAudioStreamCopy"], "false")
        XCTAssertEqual(queryMap["AudioCodec"], "aac")
    }

    func testCoordinatorServerDefaultUpgradesMKVHEVCToAppleOptimizedHEVC() async throws {
        let source = MediaSource(
            id: "source-server-default-mkv-hevc",
            itemID: "item-server-default-mkv-hevc",
            name: "MKV HEVC source",
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "eac3",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: URL(string: "https://example.com/Videos/item-server-default-mkv-hevc/master.m3u8?MediaSourceId=source-server-default-mkv-hevc&VideoCodec=hevc&AllowVideoStreamCopy=true&AllowAudioStreamCopy=true&Container=fmp4&SegmentContainer=fmp4")
        )
        let client = MockPlaybackAPIClient(configuration: server, sources: ["item-server-default-mkv-hevc": [source]])
        let coordinator = PlaybackCoordinator(apiClient: client)

        let selection = try await coordinator.resolvePlayback(
            itemID: "item-server-default-mkv-hevc",
            mode: .balanced,
            allowTranscodingFallbackInPerformance: true,
            transcodeProfile: .serverDefault
        )

        guard case .transcode = selection.decision.route else {
            XCTFail("Expected transcode route")
            return
        }

        let queryMap = queryMap(from: selection.assetURL)
        XCTAssertEqual(queryMap["VideoCodec"], "hevc")
        XCTAssertEqual(queryMap["AllowVideoStreamCopy"], "false")
        XCTAssertEqual(queryMap["Container"], "fmp4")
        XCTAssertEqual(queryMap["SegmentContainer"], "fmp4")
        XCTAssertEqual(queryMap["BreakOnNonKeyFrames"], "False")
    }

    func testCoordinatorForceH264ProfileDisablesVideoCopy() async throws {
        // Use preferAudioTranscodeOnly: false so this test exercises the audio-copy path.
        let configWithAudioCopy = ServerConfiguration(
            serverURL: URL(string: "https://example.com")!,
            preferAudioTranscodeOnly: false
        )
        let source = MediaSource(
            id: "source-2",
            itemID: "item-2",
            name: "HEVC source",
            container: "avi",
            videoCodec: "hevc",
            audioCodec: "eac3",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: URL(string: "https://example.com/Videos/item-2/master.m3u8?MediaSourceId=source-2&VideoCodec=hevc")
        )
        let client = MockPlaybackAPIClient(configuration: configWithAudioCopy, sources: ["item-2": [source]])
        let coordinator = PlaybackCoordinator(apiClient: client)

        let selection = try await coordinator.resolvePlayback(
            itemID: "item-2",
            mode: .balanced,
            allowTranscodingFallbackInPerformance: true,
            transcodeProfile: .forceH264Transcode
        )

        guard case .transcode = selection.decision.route else {
            XCTFail("Expected transcode route")
            return
        }

        let queryMap = queryMap(from: selection.assetURL)
        XCTAssertEqual(queryMap["VideoCodec"], "h264")
        XCTAssertEqual(queryMap["AllowVideoStreamCopy"], "false")
        XCTAssertEqual(queryMap["AudioCodec"], "eac3")
        XCTAssertEqual(queryMap["AllowAudioStreamCopy"], "true")
        XCTAssertEqual(queryMap["Container"], "ts")
        XCTAssertEqual(queryMap["SegmentContainer"], "ts")
        XCTAssertEqual(queryMap["BreakOnNonKeyFrames"], "False")
    }

    func testCoordinatorForceH264ProfileStripsHEVCConstraintsAndDeduplicatesKeys() async throws {
        // Use preferAudioTranscodeOnly: false so this test exercises the audio-copy path.
        let configWithAudioCopy = ServerConfiguration(
            serverURL: URL(string: "https://example.com")!,
            preferAudioTranscodeOnly: false
        )
        let source = MediaSource(
            id: "source-3",
            itemID: "item-3",
            name: "HEVC source with stale params",
            container: "avi",
            videoCodec: "hevc",
            audioCodec: "eac3",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: URL(
                string: "https://example.com/Videos/item-3/master.m3u8?MediaSourceId=source-3&VideoCodec=hevc&AllowVideoStreamCopy=true&allowVideoStreamCopy=true&hevc-level=150&hevc-profile=main10&hevc-videobitdepth=10&AudioCodec=aac,ac3"
            )
        )
        let client = MockPlaybackAPIClient(configuration: configWithAudioCopy, sources: ["item-3": [source]])
        let coordinator = PlaybackCoordinator(apiClient: client)

        let selection = try await coordinator.resolvePlayback(
            itemID: "item-3",
            mode: .balanced,
            allowTranscodingFallbackInPerformance: true,
            transcodeProfile: .forceH264Transcode
        )

        guard case .transcode = selection.decision.route else {
            XCTFail("Expected transcode route")
            return
        }

        let lowerMap = lowercasedQueryMap(from: selection.assetURL)
        let names = queryNames(from: selection.assetURL)

        XCTAssertEqual(lowerMap["videocodec"], "h264")
        XCTAssertEqual(lowerMap["allowvideostreamcopy"], "false")
        XCTAssertEqual(lowerMap["allowaudiostreamcopy"], "true")
        XCTAssertEqual(lowerMap["audiocodec"], "eac3")
        XCTAssertEqual(lowerMap["requireavc"], "true")
        XCTAssertNil(lowerMap["hevc-level"])
        XCTAssertNil(lowerMap["hevc-profile"])
        XCTAssertNil(lowerMap["hevc-videobitdepth"])
        XCTAssertEqual(names.filter { $0 == "allowvideostreamcopy" }.count, 1)
    }

    // MARK: - TTFF Tuning Tests

    func testTTFFTuningConfigurationDefaults() {
        let config = TTFFTuningConfiguration.default
        XCTAssertEqual(config.hlsSegmentLengthSeconds, 3)
        XCTAssertEqual(config.hlsMinSegments, 1)
        XCTAssertTrue(config.disableSubtitleBurnIn)
        XCTAssertEqual(config.directPlayForwardBufferDuration, 2.0)
        XCTAssertEqual(config.remuxForwardBufferDuration, 4.0)
        XCTAssertEqual(config.transcodeForwardBufferDuration, 6.0)
        XCTAssertFalse(config.directPlayWaitsToMinimizeStalling)
        XCTAssertFalse(config.remuxWaitsToMinimizeStalling)
        XCTAssertTrue(config.transcodeWaitsToMinimizeStalling)
        XCTAssertTrue(config.preferProgressiveDirectPlay)
    }

    func testTranscodeURLContainsSegmentLengthAndMinSegments() {
        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "segment-test",
                itemID: "item-seg",
                name: "segment test",
                container: "avi",
                videoCodec: "hevc",
                audioCodec: "eac3",
                supportsDirectPlay: false,
                supportsDirectStream: false,
                directStreamURL: nil,
                directPlayURL: nil,
                transcodeURL: nil
            )
        ]

        let decision = engine.decide(itemID: "item-seg", sources: sources, configuration: server, token: "abc")

        guard case let .transcode(url) = decision?.route else {
            XCTFail("Expected transcode route")
            return
        }

        let qmap = queryMap(from: url)
        XCTAssertEqual(qmap["SegmentLength"], "3")
        XCTAssertEqual(qmap["MinSegments"], "1")
    }

    func testTranscodeURLDisablesSubtitleBurnIn() {
        let engine = PlaybackDecisionEngine()
        let sources = [
            MediaSource(
                id: "sub-test",
                itemID: "item-sub",
                name: "sub test",
                container: "avi",
                videoCodec: "h264",
                audioCodec: "dts",
                supportsDirectPlay: false,
                supportsDirectStream: false,
                directStreamURL: nil,
                directPlayURL: nil,
                transcodeURL: nil
            )
        ]

        let decision = engine.decide(itemID: "item-sub", sources: sources, configuration: server, token: "abc")

        guard case let .transcode(url) = decision?.route else {
            XCTFail("Expected transcode route")
            return
        }

        let qmap = queryMap(from: url)
        XCTAssertEqual(qmap["SubtitleMethod"], "External")
        XCTAssertNil(qmap["SubtitleStreamIndex"])
    }

    func testDirectPlayProgressiveURLGeneration() {
        let engine = PlaybackDecisionEngine()
        let source = MediaSource(
            id: "dp-source",
            itemID: "item-dp",
            name: "Direct",
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            supportsDirectPlay: true,
            supportsDirectStream: true,
            directStreamURL: URL(string: "https://example.com/direct.mp4"),
            directPlayURL: URL(string: "https://example.com/direct.mp4")
        )

        let progressiveURL = engine.directPlayProgressiveURL(
            itemID: "item-dp",
            source: source,
            configuration: server,
            token: "test-token"
        )

        XCTAssertNotNil(progressiveURL)
        guard let url = progressiveURL else { return }
        XCTAssertTrue(url.absoluteString.contains("/Videos/item-dp/stream"))
        let qmap = queryMap(from: url)
        XCTAssertEqual(qmap["static"], "true")
        XCTAssertEqual(qmap["MediaSourceId"], "dp-source")
        XCTAssertEqual(qmap["api_key"], "test-token")
    }

    func testDirectPlayProgressiveURLDisabledWhenConfigured() {
        let config = TTFFTuningConfiguration(preferProgressiveDirectPlay: false)
        let engine = PlaybackDecisionEngine(ttffTuning: config)
        let source = MediaSource(
            id: "dp-off",
            itemID: "item-off",
            name: "Direct",
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            supportsDirectPlay: true,
            supportsDirectStream: true,
            directStreamURL: URL(string: "https://example.com/direct.mp4"),
            directPlayURL: URL(string: "https://example.com/direct.mp4")
        )

        let progressiveURL = engine.directPlayProgressiveURL(
            itemID: "item-off",
            source: source,
            configuration: server,
            token: "token"
        )

        XCTAssertNil(progressiveURL)
    }

    func testCustomSegmentLengthInTranscodeURL() {
        let config = TTFFTuningConfiguration(hlsSegmentLengthSeconds: 6, hlsMinSegments: 2)
        let engine = PlaybackDecisionEngine(ttffTuning: config)
        let sources = [
            MediaSource(
                id: "custom-seg",
                itemID: "item-custom",
                name: "custom",
                container: "avi",
                videoCodec: "hevc",
                audioCodec: "dts",
                supportsDirectPlay: false,
                supportsDirectStream: false,
                directStreamURL: nil,
                directPlayURL: nil,
                transcodeURL: nil
            )
        ]

        let decision = engine.decide(itemID: "item-custom", sources: sources, configuration: server, token: "abc")

        guard case let .transcode(url) = decision?.route else {
            XCTFail("Expected transcode route")
            return
        }

        let qmap = queryMap(from: url)
        XCTAssertEqual(qmap["SegmentLength"], "6")
        XCTAssertEqual(qmap["MinSegments"], "2")
    }

    private func queryMap(from url: URL) -> [String: String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })
    }

    private func lowercasedQueryMap(from url: URL) -> [String: String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
            guard let value = item.value else { return nil }
            return (item.name.lowercased(), value.lowercased())
        })
    }

    private func queryNames(from url: URL) -> [String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return (components?.queryItems ?? []).map { $0.name.lowercased() }
    }
}

private final class PlaybackCoordinatorTestAPIClient: JellyfinAPIClientProtocol, @unchecked Sendable {
    private let configuration: ServerConfiguration
    private let session: UserSession
    private let sourcesByItemID: [String: [MediaSource]]

    init(
        configuration: ServerConfiguration,
        session: UserSession,
        sourcesByItemID: [String: [MediaSource]]
    ) {
        self.configuration = configuration
        self.session = session
        self.sourcesByItemID = sourcesByItemID
    }

    func currentConfiguration() async -> ServerConfiguration? {
        configuration
    }

    func currentSession() async -> UserSession? {
        session
    }

    func configure(server: ServerConfiguration) async throws {}
    func testConnection(serverURL: URL) async throws {}
    func authenticate(credentials: UserCredentials) async throws -> UserSession { session }
    func signOut() async {}
    func initiateQuickConnect(serverURL: URL) async throws -> QuickConnectState { throw AppError.unknown }
    func pollQuickConnect(secret: String) async throws -> UserSession? { nil }
    func fetchUserViews() async throws -> [LibraryView] { [] }
    func fetchHomeFeed(since: Date?) async throws -> HomeFeed { .empty }
    func fetchItem(id: String) async throws -> MediaItem { MediaItem(id: id, name: id) }
    func fetchItemDetail(id: String) async throws -> MediaDetail { MediaDetail(item: MediaItem(id: id, name: id)) }
    func fetchSeasons(seriesID: String) async throws -> [MediaItem] { [] }
    func fetchEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] { [] }
    func fetchNextUpEpisode(seriesID: String) async throws -> MediaItem? { nil }
    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] { [] }

    func fetchPlaybackSources(itemID: String) async throws -> [MediaSource] {
        sourcesByItemID[itemID] ?? []
    }

    func fetchPlaybackSources(itemID: String, options: PlaybackInfoOptions) async throws -> [MediaSource] {
        _ = options
        return sourcesByItemID[itemID] ?? []
    }

    func imageURL(for itemID: String, type: JellyfinImageType, width: Int?, quality: Int?) async -> URL? { nil }
    func prefetchImages(for items: [MediaItem]) async {}
    func reportPlayback(progress: PlaybackProgressUpdate) async throws {}
    func reportPlayed(itemID: String) async throws {}
}

private struct FixedPlanCapabilityEngine: CapabilityEngineProtocol {
    let plan: PlaybackPlan

    func computePlan(input: PlaybackPlanningInput) -> PlaybackPlan {
        _ = input
        return plan
    }
}

private struct PassthroughMediaProbe: MediaProbeProtocol {
    func probe(itemID: String, source: MediaSource) -> MediaProbeResult {
        MediaProbeResult(
            itemID: itemID,
            sourceID: source.id,
            container: source.normalizedContainer,
            directPlayURL: source.directPlayURL,
            directStreamURL: source.directStreamURL,
            transcodeURL: source.transcodeURL,
            videoCodec: source.normalizedVideoCodec,
            audioCodec: source.normalizedAudioCodec,
            videoBitDepth: source.videoBitDepth,
            videoRangeType: source.videoRangeType,
            dvProfile: source.dvProfile,
            dvLevel: source.dvLevel,
            dvBlSignalCompatibilityId: source.dvBlSignalCompatibilityId,
            hdr10PlusPresent: source.hdr10PlusPresentFlag ?? false,
            audioTracks: [],
            subtitleTracks: [],
            hasKeyframeIndex: false,
            confidence: .server
        )
    }
}

private final class MockPlaybackAPIClient: JellyfinAPIClientProtocol, @unchecked Sendable {
    private let configuration: ServerConfiguration
    private let session: UserSession
    private let sources: [String: [MediaSource]]

    init(configuration: ServerConfiguration, sources: [String: [MediaSource]]) {
        self.configuration = configuration
        self.sources = sources
        self.session = UserSession(userID: "user-1", username: "Flo", token: "token-1")
    }

    func currentConfiguration() async -> ServerConfiguration? {
        configuration
    }

    func currentSession() async -> UserSession? {
        session
    }

    func configure(server: ServerConfiguration) async throws {
        _ = server
    }

    func testConnection(serverURL: URL) async throws {
        _ = serverURL
    }

    func authenticate(credentials: UserCredentials) async throws -> UserSession {
        _ = credentials
        return session
    }

    func signOut() async {}
    func initiateQuickConnect(serverURL: URL) async throws -> QuickConnectState { throw AppError.unknown }
    func pollQuickConnect(secret: String) async throws -> UserSession? { nil }

    func fetchUserViews() async throws -> [Shared.LibraryView] {
        []
    }

    func fetchHomeFeed(since: Date?) async throws -> HomeFeed {
        _ = since
        return .empty
    }

    func fetchItemDetail(id: String) async throws -> MediaDetail {
        _ = id
        throw AppError.network("Not implemented for tests.")
    }

    func fetchLibraryItems(query: LibraryQuery) async throws -> [MediaItem] {
        _ = query
        return []
    }

    func fetchPlaybackSources(itemID: String) async throws -> [MediaSource] {
        sources[itemID] ?? []
    }

    func fetchPlaybackSources(itemID: String, options: PlaybackInfoOptions) async throws -> [MediaSource] {
        _ = options
        return try await fetchPlaybackSources(itemID: itemID)
    }

    func imageURL(for itemID: String, type: JellyfinImageType, width: Int?, quality: Int?) async -> URL? {
        _ = itemID
        _ = type
        _ = width
        _ = quality
        return nil
    }

    func reportPlayback(progress: PlaybackProgressUpdate) async throws {
        _ = progress
    }

    func reportPlayed(itemID: String) async throws {
        _ = itemID
    }

    func fetchItem(id: String) async throws -> MediaItem {
        throw AppError.network("Not implemented for tests.")
    }

    func fetchSeasons(seriesID: String) async throws -> [MediaItem] { [] }
    func fetchEpisodes(seriesID: String, seasonID: String) async throws -> [MediaItem] { [] }
    func fetchNextUpEpisode(seriesID: String) async throws -> MediaItem? { nil }
}

final class PlaybackTrackMatcherTests: XCTestCase {
    func testBestOptionIndexPrefersExactDisplayNameMatch() {
        let track = MediaTrack(
            id: "track-1",
            title: "English 5.1",
            language: "eng",
            codec: "eac3",
            isDefault: false,
            index: 1
        )
        let options: [MediaSelectionOptionDescriptor] = [
            .init(optionIndex: 0, displayName: "French"),
            .init(optionIndex: 1, displayName: "English 5.1")
        ]

        let selected = PlaybackTrackMatcher.bestOptionIndex(for: track, options: options)

        XCTAssertEqual(selected, 1)
    }

    func testBestOptionIndexUsesLanguageWhenTitleDoesNotMatch() {
        let track = MediaTrack(
            id: "track-2",
            title: "Main Audio",
            language: "fr",
            codec: "aac",
            isDefault: true,
            index: 0
        )
        let options: [MediaSelectionOptionDescriptor] = [
            .init(optionIndex: 0, displayName: "English", languageIdentifier: "en"),
            .init(optionIndex: 1, displayName: "Français", languageIdentifier: "fr-FR")
        ]

        let selected = PlaybackTrackMatcher.bestOptionIndex(for: track, options: options)

        XCTAssertEqual(selected, 1)
    }

    func testBestOptionIndexPrefersForcedSubtitleOptionWhenRequested() {
        let track = MediaTrack(
            id: "track-3",
            title: "English Forced",
            language: "en",
            codec: "subrip",
            isDefault: false,
            index: 3
        )
        let options: [MediaSelectionOptionDescriptor] = [
            .init(optionIndex: 0, displayName: "English", languageIdentifier: "en", isForced: false),
            .init(optionIndex: 1, displayName: "English", languageIdentifier: "en", isForced: true)
        ]

        let selected = PlaybackTrackMatcher.bestOptionIndex(for: track, options: options)

        XCTAssertEqual(selected, 1)
    }

    func testBestOptionIndexReturnsNilWhenNoSignalsMatch() {
        let track = MediaTrack(
            id: "track-4",
            title: "Unknown",
            language: nil,
            codec: nil,
            isDefault: false,
            index: 4
        )
        let options: [MediaSelectionOptionDescriptor] = [
            .init(optionIndex: 0, displayName: "Option A"),
            .init(optionIndex: 1, displayName: "Option B")
        ]

        let selected = PlaybackTrackMatcher.bestOptionIndex(for: track, options: options)

        XCTAssertNil(selected)
    }
}
