@testable import PlaybackEngine
import Shared
import XCTest

final class HLSVariantSelectorTests: XCTestCase {
    func testServerDefaultPrefersDolbyVisionHEVCStreamCopyVariant() {
        let variants = HLSVariantSelector.parseVariants(manifest: sampleManifest, masterURL: sampleMasterURL)
        let source = makeSource(videoRange: "DolbyVision")

        let selected = HLSVariantSelector.preferredVariant(
            from: variants,
            playbackPolicy: .originalLockHDRDV,
            activeProfile: .serverDefault,
            source: source,
            itemPrefersDolbyVision: true,
            allowSDRFallback: false,
            strictQualityMode: true
        )

        XCTAssertNotNil(selected)
        XCTAssertEqual(selected?.query["videocodec"], "hevc")
        XCTAssertEqual(selected?.query["allowvideostreamcopy"], "true")
        XCTAssertEqual(selected?.videoRange.uppercased(), "PQ")
    }

    func testAppleOptimizedPrefersHEVCVariant() {
        let variants = HLSVariantSelector.parseVariants(manifest: sampleManifest, masterURL: sampleMasterURL)
        let source = makeSource(videoRange: "DolbyVision")

        let selected = HLSVariantSelector.preferredVariant(
            from: variants,
            playbackPolicy: .auto,
            activeProfile: .appleOptimizedHEVC,
            source: source,
            itemPrefersDolbyVision: true,
            allowSDRFallback: true,
            strictQualityMode: false
        )

        XCTAssertNotNil(selected)
        XCTAssertEqual(selected?.query["videocodec"], "hevc")
        XCTAssertEqual(selected?.normalizedCodec, "hevc")
    }

    func testForceH264PrefersH264Variant() {
        let variants = HLSVariantSelector.parseVariants(manifest: sampleManifest, masterURL: sampleMasterURL)

        let selected = HLSVariantSelector.preferredVariant(
            from: variants,
            playbackPolicy: .auto,
            activeProfile: .forceH264Transcode,
            source: makeSource(videoRange: nil),
            itemPrefersDolbyVision: false,
            allowSDRFallback: true,
            strictQualityMode: false
        )

        XCTAssertNotNil(selected)
        XCTAssertEqual(selected?.query["videocodec"], "h264")
        XCTAssertEqual(selected?.normalizedCodec, "h264")
    }

    func testParseVariantsPropagatesAPIKeyToRelativeVariantURLs() {
        let variants = HLSVariantSelector.parseVariants(manifest: sampleManifest, masterURL: sampleMasterURL)

        XCTAssertEqual(variants.count, 3)
        for variant in variants {
            let components = URLComponents(url: variant.resolvedURL, resolvingAgainstBaseURL: false)
            let apiKey = components?.queryItems?.first(where: { $0.name.lowercased() == "api_key" })?.value
            XCTAssertEqual(apiKey, "secret-token")
        }
    }

    func testParseVariantsPropagatesResumeQueryItemsToRelativeVariantURLs() {
        let masterURL = URL(
            string: "https://example.com/Videos/abcd/master.m3u8?api_key=secret-token&StartTimeTicks=420000000"
        )!
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=12000000,RESOLUTION=1920x1080,CODECS="hvc1.1.6.L123.B0,mp4a.40.2"
        main.m3u8
        """

        let variants = HLSVariantSelector.parseVariants(manifest: manifest, masterURL: masterURL)

        XCTAssertEqual(variants.count, 1)
        let items = URLComponents(url: variants[0].resolvedURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query: [String: String] = Dictionary(uniqueKeysWithValues: items.compactMap { item in
            guard let value = item.value else { return nil }
            return (item.name.lowercased(), value)
        })
        XCTAssertEqual(query["api_key"], "secret-token")
        XCTAssertEqual(query["starttimeticks"], "420000000")
    }

    func testVariantSelectorChooses4KHEVCDolbyVisionWhenAvailable() {
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=22000000,VIDEO-RANGE=PQ,CODECS="hvc1.2.4.L153.B0,mp4a.40.2",SUPPLEMENTAL-CODECS="dvh1.08.06/db1p",RESOLUTION=3840x2160
        v4k-dv.m3u8?VideoCodec=hevc&AllowVideoStreamCopy=true
        #EXT-X-STREAM-INF:BANDWIDTH=16000000,VIDEO-RANGE=PQ,CODECS="hvc1.2.4.L150.B0,mp4a.40.2",RESOLUTION=3840x2160
        v4k-hevc.m3u8?VideoCodec=hevc&AllowVideoStreamCopy=true
        #EXT-X-STREAM-INF:BANDWIDTH=22000000,VIDEO-RANGE=SDR,CODECS="avc1.4d402a,mp4a.40.2",RESOLUTION=3840x2160
        v4k-h264.m3u8?VideoCodec=h264&AllowVideoStreamCopy=false
        """

        let variants = HLSVariantSelector.parseVariants(manifest: manifest, masterURL: sampleMasterURL)
        let selected = HLSVariantSelector.preferredVariant(
            from: variants,
            playbackPolicy: .originalLockHDRDV,
            activeProfile: .serverDefault,
            source: makeSource(videoRange: "DolbyVision"),
            itemPrefersDolbyVision: true,
            allowSDRFallback: false,
            strictQualityMode: true
        )

        XCTAssertEqual(selected?.isLikely4K, true)
        XCTAssertEqual(selected?.isDolbyVisionSignaled, true)
        XCTAssertEqual(selected?.normalizedCodec, "hevc")
    }

    func testOriginalLockReturnsNilWhenOnlyH264SDRVariantsExist() {
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=12000000,VIDEO-RANGE=SDR,CODECS="avc1.640028,mp4a.40.2",RESOLUTION=3840x2160
        v4k-h264.m3u8?VideoCodec=h264&AllowVideoStreamCopy=false
        """

        let variants = HLSVariantSelector.parseVariants(manifest: manifest, masterURL: sampleMasterURL)
        let selected = HLSVariantSelector.preferredVariant(
            from: variants,
            playbackPolicy: .originalLockHDRDV,
            activeProfile: .serverDefault,
            source: makeSource(videoRange: "DolbyVision"),
            itemPrefersDolbyVision: true,
            allowSDRFallback: false,
            strictQualityMode: true
        )

        XCTAssertNil(selected)
    }

    func testSelectorSkipsImplausibleLowBitrate4KVariant() {
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=640000,VIDEO-RANGE=PQ,CODECS="hvc1.2.4.L153.B0,mp4a.40.2",SUPPLEMENTAL-CODECS="dvh1.08.06/db1p",RESOLUTION=3840x1608
        low-dv.m3u8?VideoCodec=hevc&AllowVideoStreamCopy=false
        #EXT-X-STREAM-INF:BANDWIDTH=12000000,VIDEO-RANGE=PQ,CODECS="hvc1.2.4.L153.B0,mp4a.40.2",RESOLUTION=3840x1608
        good-hevc.m3u8?VideoCodec=hevc&AllowVideoStreamCopy=false
        """

        let variants = HLSVariantSelector.parseVariants(manifest: manifest, masterURL: sampleMasterURL)
        let selected = HLSVariantSelector.preferredVariant(
            from: variants,
            playbackPolicy: .auto,
            activeProfile: .appleOptimizedHEVC,
            source: makeSource(videoRange: "HDR10"),
            itemPrefersDolbyVision: true,
            allowSDRFallback: true,
            strictQualityMode: false
        )

        XCTAssertNotNil(selected)
        XCTAssertTrue(selected?.resolvedURL.absoluteString.contains("good-hevc.m3u8") == true)
    }

    private func makeSource(videoRange: String?) -> MediaSource {
        MediaSource(
            id: "source",
            itemID: "item",
            name: "source",
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "eac3",
            videoRange: videoRange,
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: sampleMasterURL
        )
    }

    private let sampleMasterURL = URL(
        string: "https://example.com/Videos/abcd/master.m3u8?api_key=secret-token"
    )!

    private let sampleManifest = """
    #EXTM3U
    #EXT-X-STREAM-INF:BANDWIDTH=640000,AVERAGE-BANDWIDTH=640000,VIDEO-RANGE=PQ,CODECS="hvc1.2.4.L153.B0,mp4a.40.2",SUPPLEMENTAL-CODECS="dvh1.08.06/db1p",RESOLUTION=3840x1608,FRAME-RATE=23.976
    main.m3u8?AudioCodec=aac&Container=fmp4&SegmentContainer=fmp4&AllowVideoStreamCopy=true&AllowAudioStreamCopy=false&VideoCodec=hevc
    #EXT-X-STREAM-INF:BANDWIDTH=640000,AVERAGE-BANDWIDTH=640000,VIDEO-RANGE=SDR,CODECS="hvc1.1.4.L120.B0,mp4a.40.2",RESOLUTION=3840x1608,FRAME-RATE=23.976
    main.m3u8?AudioCodec=aac&Container=fmp4&SegmentContainer=fmp4&AllowVideoStreamCopy=false&AllowAudioStreamCopy=false&VideoCodec=hevc
    #EXT-X-STREAM-INF:BANDWIDTH=640000,AVERAGE-BANDWIDTH=640000,VIDEO-RANGE=SDR,CODECS="avc1.424029,mp4a.40.2",RESOLUTION=3840x1608,FRAME-RATE=23.976
    main.m3u8?AudioCodec=aac&Container=fmp4&SegmentContainer=fmp4&AllowVideoStreamCopy=false&AllowAudioStreamCopy=false&VideoCodec=h264
    """
}
