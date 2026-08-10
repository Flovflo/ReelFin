import CoreMedia
import NativeMediaCore
import XCTest

final class MatroskaParserTests: XCTestCase {
    func testCheckedRangeRejectsEndpointOverflow() {
        XCTAssertThrowsError(
            try EBMLReader().checkedRange(
                offset: Int.max - 1,
                size: 8,
                parentEnd: Int.max,
                dataCount: Int.max
            )
        ) { error in
            XCTAssertTrue(error is EBMLError)
        }
    }

    func testPayloadRangeRejectsParentEscapeWithinAvailableData() throws {
        let header = try EBMLReader().readHeader(data: Data([0xA3, 0x82, 0x00, 0x00]), offset: 0)

        XCTAssertThrowsError(
            try EBMLReader().payloadRange(
                for: header,
                elementOffset: 0,
                parentEnd: 3,
                dataCount: 4
            )
        ) { error in
            XCTAssertTrue(error is EBMLError)
        }
    }

    func testPayloadRangeRejectsNestedUnknownSize() throws {
        let header = try EBMLReader().readHeader(data: Data([0xAE, 0xFF]), offset: 0)

        XCTAssertThrowsError(
            try EBMLReader().payloadRange(
                for: header,
                elementOffset: 0,
                parentEnd: 4,
                dataCount: 4
            )
        ) { error in
            XCTAssertTrue(error is EBMLError)
        }
    }

    func testPayloadRangeRejectsDataEscape() throws {
        let header = try EBMLReader().readHeader(data: Data([0xA3, 0x82, 0x00, 0x00]), offset: 0)

        XCTAssertThrowsError(
            try EBMLReader().payloadRange(
                for: header,
                elementOffset: 0,
                parentEnd: 4,
                dataCount: 3
            )
        ) { error in
            XCTAssertTrue(error is EBMLError)
        }
    }

    func testPayloadRangeAllowsZeroSizePayloadAndUnknownRootSegment() throws {
        let reader = EBMLReader()
        let emptyHeader = try reader.readHeader(data: Data([0xEC, 0x80]), offset: 0)
        let segmentHeader = try reader.readHeader(
            data: Data([0x18, 0x53, 0x80, 0x67, 0xFF, 0x00, 0x00, 0x00]),
            offset: 0
        )

        XCTAssertEqual(
            try reader.payloadRange(for: emptyHeader, elementOffset: 0, parentEnd: 2, dataCount: 2),
            2..<2
        )
        XCTAssertEqual(
            try reader.payloadRange(
                for: segmentHeader,
                elementOffset: 0,
                parentEnd: 8,
                dataCount: 8,
                unknownSizeEnd: 8
            ),
            5..<8
        )
    }

    func testRejectsCodecPrivateEscapingTrackEntryParent() {
        let codecPrivateWithoutPayload: [UInt8] = [0xAE, 0x83, 0x63, 0xA2, 0xFE]
        let sibling = element([0xEC], payload: Array(repeating: 0, count: 124))
        let tracks = element([0x16, 0x54, 0xAE, 0x6B], payload: codecPrivateWithoutPayload + sibling)

        assertMatroskaError(mkv([tracks]))
    }

    func testRejectsSimpleBlockEscapingClusterParent() {
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: [0xA3, 0xFE])
        let sibling = element([0xEC], payload: Array(repeating: 0, count: 124))

        assertMatroskaError(mkv([cluster, sibling]))
    }

    func testRejectsBlockEscapingBlockGroupParent() {
        let blockGroup = element([0xA0], payload: [0xA1, 0xFE])
        let sibling = element([0xEC], payload: Array(repeating: 0, count: 124))
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: blockGroup + sibling)

        assertMatroskaError(mkv([cluster]))
    }

    func testRejectsDurationEscapingInfoParent() {
        let durationWithoutPayload: [UInt8] = [0x15, 0x49, 0xA9, 0x66, 0x83, 0x44, 0x89, 0x88]
        let sibling = element([0xEC], payload: Array(repeating: 0, count: 6))

        assertMatroskaError(mkv([durationWithoutPayload, sibling]))
    }

    func testRejectsCueTimeEscapingCuePointParent() {
        let cuePointWithoutPayload: [UInt8] = [0xBB, 0x82, 0xB3, 0x88]
        let sibling = element([0xEC], payload: Array(repeating: 0, count: 6))
        let cues = element([0x1C, 0x53, 0xBB, 0x6B], payload: cuePointWithoutPayload + sibling)

        assertMatroskaError(mkv([cues]))
    }

    func testRejectsCueTrackEscapingTrackPositionsParent() {
        let positionsWithoutPayload: [UInt8] = [0xB7, 0x82, 0xF7, 0x88]
        let sibling = element([0xEC], payload: Array(repeating: 0, count: 6))
        let cuePoint = element([0xBB], payload: positionsWithoutPayload + sibling)
        let cues = element([0x1C, 0x53, 0xBB, 0x6B], payload: cuePoint)

        assertMatroskaError(mkv([cues]))
    }

    func testRejectsMalformedSeekEntryInsteadOfSilentlyDroppingIt() {
        let seekWithoutPayload: [UInt8] = [0x4D, 0xBB, 0x83, 0x53, 0xAB, 0x84]
        let sibling = element([0xEC], payload: [0x00, 0x00])
        let seekHead = element([0x11, 0x4D, 0x9B, 0x74], payload: seekWithoutPayload + sibling)

        assertMatroskaError(mkv([seekHead]))
    }

    func testRejectsNestedUnknownSizeTrackEntry() {
        let tracks = element([0x16, 0x54, 0xAE, 0x6B], payload: [0xAE, 0xFF])

        assertMatroskaError(mkv([tracks]))
    }

    func testRejectsNestedUnknownSizeBlockGroup() {
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: [0xA0, 0xFF])

        assertMatroskaError(mkv([cluster]))
    }

    func testRejectsEightByteVINTPayloadSize() {
        let hugeCodecPrivate: [UInt8] = [0x63, 0xA2, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE]
        let track = element([0xAE], payload: hugeCodecPrivate)
        let tracks = element([0x16, 0x54, 0xAE, 0x6B], payload: track)

        assertMatroskaError(mkv([tracks]))
    }

    func testRejectsTruncatedSimpleBlockPayload() {
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: [0xA3, 0x88])

        assertMatroskaError(mkv([cluster]))
    }

    func testAllowsUnknownSizeRootSegmentAndZeroSizeChild() throws {
        let data = Data(element([0x1A, 0x45, 0xDF, 0xA3], payload: []))
            + Data([0x18, 0x53, 0x80, 0x67, 0xFF])
            + Data(element([0xEC], payload: []))

        let segment = try MatroskaSegmentParser().parse(data: data)

        XCTAssertEqual(segment.segmentPayloadOffset, 10)
        XCTAssertNil(segment.segmentEndOffset)
        XCTAssertEqual(segment.parsedUntilOffset, data.count)
    }

    func testRejectsUnrepresentableAndZeroTimecodeScale() {
        for rawScale in [UInt64(0), UInt64.max] {
            let info = element(
                [0x15, 0x49, 0xA9, 0x66],
                payload: element([0x2A, 0xD7, 0xB1], payload: uintPayload(rawScale, fixedLength: 8))
            )

            assertMatroskaError(mkv([info]))
        }
    }

    func testRejectsUnrepresentableClusterTimecode() {
        let cluster = element(
            [0x1F, 0x43, 0xB6, 0x75],
            payload: element([0xE7], payload: uintPayload(UInt64.max, fixedLength: 8))
        )

        assertMatroskaError(mkv([cluster]))
    }

    func testRejectsBlockDurationMultiplicationOverflow() {
        let info = element(
            [0x15, 0x49, 0xA9, 0x66],
            payload: element([0x2A, 0xD7, 0xB1], payload: [0x02])
        )
        let block = element([0xA1], payload: [0x81, 0x00, 0x00, 0x00, 0xAA])
        let duration = element(
            [0x9B],
            payload: uintPayload(UInt64(Int64.max), fixedLength: 8)
        )
        let cluster = element(
            [0x1F, 0x43, 0xB6, 0x75],
            payload: element([0xA0], payload: block + duration)
        )

        assertMatroskaError(mkv([info, cluster]))
    }

    func testRejectsPacketTimestampAdditionOverflow() {
        let info = element(
            [0x15, 0x49, 0xA9, 0x66],
            payload: element([0x2A, 0xD7, 0xB1], payload: [0x01])
        )
        let timecode = element(
            [0xE7],
            payload: uintPayload(UInt64(Int64.max), fixedLength: 8)
        )
        let block = element([0xA3], payload: [0x81, 0x00, 0x01, 0x80, 0xAA])
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: timecode + block)

        assertMatroskaError(mkv([info, cluster]))
    }

    func testRejectsPacketTimestampMultiplicationOverflow() {
        let info = element(
            [0x15, 0x49, 0xA9, 0x66],
            payload: element(
                [0x2A, 0xD7, 0xB1],
                payload: uintPayload(UInt64(Int64.max), fixedLength: 8)
            )
        )
        let timecode = element([0xE7], payload: [0x02])
        let block = element([0xA3], payload: [0x81, 0x00, 0x00, 0x80, 0xAA])
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: timecode + block)

        assertMatroskaError(mkv([info, cluster]))
    }

    func testRejectsUnrepresentableTrackIntegerFields() {
        let oversized = uintPayload(UInt64.max, fixedLength: 8)
        let fields: [[UInt8]] = [
            element([0xD7], payload: oversized),
            element([0x83], payload: oversized),
            element([0x23, 0xE3, 0x83], payload: oversized),
            element([0xE0], payload: element([0xB0], payload: oversized)),
            element([0xE0], payload: element([0xBA], payload: oversized)),
            element([0xE0], payload: element([0x55, 0xB0], payload:
                element([0x55, 0xBB], payload: oversized)
            )),
            element([0xE0], payload: element([0x55, 0xB0], payload:
                element([0x55, 0xBA], payload: oversized)
            )),
            element([0xE0], payload: element([0x55, 0xB0], payload:
                element([0x55, 0xB1], payload: oversized)
            )),
            element([0xE0], payload: element([0x55, 0xB0], payload:
                element([0x55, 0xB2], payload: oversized)
            )),
            element([0xE0], payload: element([0x55, 0xB0], payload:
                element([0x55, 0xBC], payload: oversized)
            )),
            element([0xE0], payload: element([0x55, 0xB0], payload:
                element([0x55, 0xBD], payload: oversized)
            )),
            element([0xE1], payload: element([0x9F], payload: oversized)),
            element([0xE1], payload: element([0x62, 0x64], payload: oversized))
        ]

        for field in fields {
            let track = element([0xAE], payload: field)
            let tracks = element([0x16, 0x54, 0xAE, 0x6B], payload: track)
            assertMatroskaError(mkv([tracks]))
        }
    }

    func testRejectsNonFiniteAndUnrepresentableSamplingFrequency() {
        let invalidRates = [Double.infinity, -Double.infinity, Double.nan, Double(CMTimeScale.max) + 1]
        for rate in invalidRates {
            let audio = element([0xE1], payload: element([0xB5], payload: doublePayload(rate)))
            let track = element([0xAE], payload: audio)
            let tracks = element([0x16, 0x54, 0xAE, 0x6B], payload: track)
            assertMatroskaError(mkv([tracks]))
        }
    }

    func testTrackTimingRejectsUnrepresentableDurationAndSampleRate() throws {
        let audio = element([0xE1], payload: element([0xB5], payload: doublePayload(48_000)))
        let trackEntry = element([0xAE], payload:
            element([0xD7], payload: [0x01]) +
            element([0x83], payload: [0x02]) +
            element([0x86], payload: Array("A_AAC".utf8)) +
            audio
        )
        let tracks = element([0x16, 0x54, 0xAE, 0x6B], payload: trackEntry)
        var track = try XCTUnwrap(MatroskaSegmentParser().parse(data: mkv([tracks])).tracks.first)
        track.defaultDuration = UInt64.max
        XCTAssertNil(MatroskaTrackTiming.defaultDuration(for: track))

        track.defaultDuration = nil
        track.audio?.sampleRate = .infinity
        XCTAssertNil(MatroskaTrackTiming.defaultDuration(for: track))
        track.audio?.sampleRate = Double(CMTimeScale.max) + 1
        XCTAssertNil(MatroskaTrackTiming.defaultDuration(for: track))
    }

    func testDemuxerHandlesNonFiniteSeekTimeWithoutTrapping() async throws {
        let track = element([0x16, 0x54, 0xAE, 0x6B], payload: element([0xAE], payload:
            element([0xD7], payload: [0x01]) +
            element([0x83], payload: [0x01]) +
            element([0x86], payload: Array("V_MPEG4/ISO/AVC".utf8))
        ))
        let firstCluster = cluster(track: 1, payload: [0x01])
        let cue = cues(timecode: 0, track: 1, clusterPosition: UInt64(track.count))
        let demuxer = MatroskaDemuxer(source: DataBackedByteSource(data: mkv([track, cue, firstCluster])))

        _ = try await demuxer.open()
        try await demuxer.seek(to: .positiveInfinity)
        let packet = try await demuxer.readNextPacket()

        XCTAssertNotNil(packet)
    }

    func testParsesLargeRepresentableTimestampValues() throws {
        let info = element(
            [0x15, 0x49, 0xA9, 0x66],
            payload: element([0x2A, 0xD7, 0xB1], payload: uintPayload(1_000_000_000))
        )
        let timecode = element([0xE7], payload: uintPayload(1_000_000))
        let block = element([0xA3], payload: [0x81, 0x00, 0x00, 0x80, 0xAA])
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: timecode + block)

        let segment = try MatroskaSegmentParser().parse(data: mkv([info, cluster]))

        XCTAssertEqual(segment.packets.first?.timestamp.pts.value, 1_000_000_000_000_000)
    }

    func testParsesBasicTrackMetadata() throws {
        let data = mkv([
            element([0x15, 0x49, 0xA9, 0x66], payload: element([0x2A, 0xD7, 0xB1], payload: [0x0F, 0x42, 0x40])),
            element([0x16, 0x54, 0xAE, 0x6B], payload: element([0xAE], payload:
                element([0xD7], payload: [0x01]) +
                element([0x83], payload: [0x01]) +
                element([0x86], payload: Array("V_MPEG4/ISO/AVC".utf8)) +
                element([0x22, 0xB5, 0x9C], payload: Array("eng".utf8)) +
                element([0x53, 0x6E], payload: Array("Main".utf8)) +
                element([0xE0], payload:
                    element([0xB0], payload: [0x07, 0x80]) +
                    element([0xBA], payload: [0x04, 0x38])
                )
            ))
        ])

        let segment = try MatroskaSegmentParser().parse(data: data)

        XCTAssertEqual(segment.tracks.count, 1)
        XCTAssertEqual(segment.tracks[0].codec, "h264")
        XCTAssertEqual(segment.tracks[0].language, "eng")
        XCTAssertEqual(segment.tracks[0].video?.width, 1920)
        XCTAssertEqual(segment.tracks[0].video?.height, 1080)
    }

    func testParsesSimpleBlockPacket() throws {
        let simpleBlock = element([0xA3], payload: [0x81, 0x00, 0x00, 0x80, 0x01, 0x02])
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [0x00]) + simpleBlock)
        let data = mkv([cluster])

        let segment = try MatroskaSegmentParser().parse(data: data)

        XCTAssertEqual(segment.packets.count, 1)
        XCTAssertEqual(segment.packets[0].trackID, 1)
        XCTAssertTrue(segment.packets[0].isKeyframe)
        XCTAssertEqual(segment.packets[0].data, Data([0x01, 0x02]))
    }

    func testMapsSimpleBlockTimestampWithClusterTimecode() throws {
        let simpleBlock = element([0xA3], payload: [0x81, 0x00, 0x0A, 0x80, 0xAA])
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [0x05]) + simpleBlock)
        let data = mkv([cluster])

        let segment = try MatroskaSegmentParser().parse(data: data)

        XCTAssertEqual(segment.packets.count, 1)
        XCTAssertEqual(segment.packets[0].timestamp.pts.seconds, 0.015, accuracy: 0.0001)
    }

    func testExtractsXiphLacedSimpleBlockPackets() throws {
        let simpleBlock = element(
            [0xA3],
            payload: [0x81, 0x00, 0x00, 0x82, 0x01, 0x02, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE]
        )
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [0x00]) + simpleBlock)
        let data = mkv([cluster])

        let segment = try MatroskaSegmentParser().parse(data: data)

        XCTAssertEqual(segment.packets.count, 2)
        XCTAssertEqual(segment.packets[0].data, Data([0xAA, 0xBB]))
        XCTAssertEqual(segment.packets[1].data, Data([0xCC, 0xDD, 0xEE]))
    }

    func testExtractsFixedSizeLacedSimpleBlockPackets() throws {
        let simpleBlock = element(
            [0xA3],
            payload: [0x81, 0x00, 0x00, 0x84, 0x01, 0x01, 0x02, 0x03, 0x04]
        )
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [0x00]) + simpleBlock)
        let data = mkv([cluster])

        let segment = try MatroskaSegmentParser().parse(data: data)

        XCTAssertEqual(segment.packets.count, 2)
        XCTAssertEqual(segment.packets[0].data, Data([0x01, 0x02]))
        XCTAssertEqual(segment.packets[1].data, Data([0x03, 0x04]))
    }

    func testLacedPacketsAdvancePTSUsingTrackDefaultDuration() throws {
        let track = element([0xAE], payload:
            element([0xD7], payload: [0x01]) +
            element([0x83], payload: [0x02]) +
            element([0x86], payload: Array("A_AAC".utf8)) +
            element([0x23, 0xE3, 0x83], payload: [0x01, 0x45, 0x85, 0x55])
        )
        let simpleBlock = element(
            [0xA3],
            payload: [0x81, 0x00, 0x00, 0x84, 0x01, 0x11, 0x22, 0x33, 0x44]
        )
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [0x00]) + simpleBlock)
        let data = mkv([element([0x16, 0x54, 0xAE, 0x6B], payload: track), cluster])

        let segment = try MatroskaSegmentParser().parse(data: data)

        XCTAssertEqual(segment.packets.count, 2)
        XCTAssertEqual(segment.packets[0].timestamp.pts.seconds, 0, accuracy: 0.000001)
        XCTAssertEqual(segment.packets[1].timestamp.pts.seconds, 0.021333333, accuracy: 0.000001)
        XCTAssertEqual(segment.packets[0].timestamp.duration?.seconds ?? 0, 0.021333333, accuracy: 0.000001)
        XCTAssertEqual(segment.packets[1].timestamp.duration?.seconds ?? 0, 0.021333333, accuracy: 0.000001)
    }

    func testLacedEAC3PacketsAdvancePTSUsingSynthesizedAudioDuration() throws {
        let track = element([0xAE], payload:
            element([0xD7], payload: [0x01]) +
            element([0x83], payload: [0x02]) +
            element([0x86], payload: Array("A_EAC3".utf8)) +
            element([0xE1], payload:
                element([0xB5], payload: doublePayload(48_000)) +
                element([0x9F], payload: [0x06])
            )
        )
        let simpleBlock = element(
            [0xA3],
            payload: [0x81, 0x00, 0x00, 0x84, 0x01, 0x11, 0x22, 0x33, 0x44]
        )
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [0x00]) + simpleBlock)
        let data = mkv([element([0x16, 0x54, 0xAE, 0x6B], payload: track), cluster])

        let segment = try MatroskaSegmentParser().parse(data: data)

        XCTAssertEqual(segment.packets.count, 2)
        XCTAssertEqual(segment.packets[0].timestamp.pts.seconds, 0, accuracy: 0.000001)
        XCTAssertEqual(segment.packets[1].timestamp.pts.seconds, 0.032, accuracy: 0.000001)
        XCTAssertEqual(segment.packets[0].timestamp.duration?.seconds ?? 0, 0.032, accuracy: 0.000001)
        XCTAssertEqual(segment.packets[1].timestamp.duration?.seconds ?? 0, 0.032, accuracy: 0.000001)
    }

    func testExtractsEBMLLacedSimpleBlockPackets() throws {
        let simpleBlock = element(
            [0xA3],
            payload: [
                0x81, 0x00, 0x00, 0x86,
                0x02,
                0x82,
                0xC0,
                0xAA, 0xBB,
                0xCC, 0xDD, 0xEE,
                0xF0, 0xF1, 0xF2, 0xF3
            ]
        )
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [0x00]) + simpleBlock)
        let data = mkv([cluster])

        let segment = try MatroskaSegmentParser().parse(data: data)

        XCTAssertEqual(segment.packets.count, 3)
        XCTAssertEqual(segment.packets[0].data, Data([0xAA, 0xBB]))
        XCTAssertEqual(segment.packets[1].data, Data([0xCC, 0xDD, 0xEE]))
        XCTAssertEqual(segment.packets[2].data, Data([0xF0, 0xF1, 0xF2, 0xF3]))
    }

    func testParsesAudioMetadataAndAppliesDefaultPacketDuration() throws {
        let track = element([0xAE], payload:
            element([0xD7], payload: [0x01]) +
            element([0x83], payload: [0x02]) +
            element([0x86], payload: Array("A_AAC".utf8)) +
            element([0x23, 0xE3, 0x83], payload: [0x01, 0x45, 0x85, 0x55]) +
            element([0xE1], payload:
                element([0xB5], payload: doublePayload(48_000)) +
                element([0x9F], payload: [0x02]) +
                element([0x62, 0x64], payload: [0x10])
            )
        )
        let simpleBlock = element([0xA3], payload: [0x81, 0x00, 0x00, 0x80, 0x21, 0x10])
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [0x00]) + simpleBlock)
        let data = mkv([element([0x16, 0x54, 0xAE, 0x6B], payload: track), cluster])

        let segment = try MatroskaSegmentParser().parse(data: data)

        XCTAssertEqual(segment.tracks[0].codec, "aac")
        XCTAssertEqual(segment.tracks[0].audio?.sampleRate, 48_000)
        XCTAssertEqual(segment.tracks[0].audio?.channels, 2)
        XCTAssertEqual(segment.tracks[0].audio?.bitDepth, 16)
        XCTAssertEqual(segment.packets[0].timestamp.duration?.seconds ?? 0, 0.021333333, accuracy: 0.000001)
    }

    func testParsesBlockGroupDurationForSubtitleTiming() throws {
        let block = element([0xA1], payload: [0x81, 0x00, 0x05, 0x00] + Array("Bonjour".utf8))
        let duration = element([0x9B], payload: [0x28])
        let group = element([0xA0], payload: block + duration)
        let cluster = element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [0x00]) + group)
        let data = mkv([cluster])

        let segment = try MatroskaSegmentParser().parse(data: data)

        XCTAssertEqual(segment.packets.count, 1)
        XCTAssertEqual(segment.packets[0].data, Data("Bonjour".utf8))
        XCTAssertEqual(segment.packets[0].timestamp.pts.seconds, 0.005, accuracy: 0.0001)
        XCTAssertEqual(segment.packets[0].timestamp.duration?.seconds ?? 0, 0.04, accuracy: 0.0001)
    }

    func testDemuxerReadsClustersBeyondInitialProbeWindow() async throws {
        let track = element([0xAE], payload:
            element([0xD7], payload: [0x01]) +
            element([0x83], payload: [0x01]) +
            element([0x86], payload: Array("V_MPEG4/ISO/AVC".utf8))
        )
        let firstCluster = cluster(track: 1, payload: [0x01])
        let filler = element([0xEC], payload: Array(repeating: 0, count: 8 * 1024 * 1024))
        let secondCluster = cluster(track: 1, payload: [0x02, 0x03])
        let data = mkv([element([0x16, 0x54, 0xAE, 0x6B], payload: track), firstCluster, filler, secondCluster])
        let source = DataBackedByteSource(data: data)
        let demuxer = MatroskaDemuxer(source: source)

        _ = try await demuxer.open()
        let first = try await demuxer.readNextPacket()
        let second = try await demuxer.readNextPacket()

        XCTAssertEqual(first?.data, Data([0x01]))
        XCTAssertEqual(second?.data, Data([0x02, 0x03]))
        let metrics = await source.metrics()
        XCTAssertGreaterThan(metrics.rangeRequestCount, 1)
    }

    func testDemuxerAppliesSynthesizedAudioDurationToStreamingClusters() async throws {
        let track = element([0xAE], payload:
            element([0xD7], payload: [0x01]) +
            element([0x83], payload: [0x02]) +
            element([0x86], payload: Array("A_EAC3".utf8)) +
            element([0xE1], payload:
                element([0xB5], payload: doublePayload(48_000)) +
                element([0x9F], payload: [0x06])
            )
        )
        let firstCluster = cluster(track: 1, payload: [0x0B, 0x77])
        let filler = element([0xEC], payload: Array(repeating: 0, count: 8 * 1024 * 1024))
        let lacedBlock = element(
            [0xA3],
            payload: [0x81, 0x00, 0x00, 0x84, 0x01, 0x11, 0x22, 0x33, 0x44]
        )
        let secondCluster = element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [0x64]) + lacedBlock)
        let data = mkv([element([0x16, 0x54, 0xAE, 0x6B], payload: track), firstCluster, filler, secondCluster])
        let source = DataBackedByteSource(data: data)
        let demuxer = MatroskaDemuxer(source: source)

        _ = try await demuxer.open()
        _ = try await demuxer.readNextPacket()
        let firstLacedPacket = try await demuxer.readNextPacket()
        let secondLacedPacket = try await demuxer.readNextPacket()
        let firstLaced = try XCTUnwrap(firstLacedPacket)
        let secondLaced = try XCTUnwrap(secondLacedPacket)

        XCTAssertEqual(firstLaced.timestamp.pts.seconds, 0.1, accuracy: 0.000001)
        XCTAssertEqual(secondLaced.timestamp.pts.seconds, 0.132, accuracy: 0.000001)
        XCTAssertEqual(secondLaced.timestamp.duration?.seconds ?? 0, 0.032, accuracy: 0.000001)
        let metrics = await source.metrics()
        XCTAssertGreaterThan(metrics.rangeRequestCount, 1)
    }

    func testDemuxerSeekUsesCueClusterPosition() async throws {
        let track = element([0x16, 0x54, 0xAE, 0x6B], payload: element([0xAE], payload:
            element([0xD7], payload: [0x01]) +
            element([0x83], payload: [0x01]) +
            element([0x86], payload: Array("V_MPEG4/ISO/AVC".utf8))
        ))
        let firstCluster = cluster(track: 1, payload: [0x01])
        let secondCluster = cluster(track: 1, payload: [0x02])
        let placeholderCue = cues(timecode: 10, track: 1, clusterPosition: UInt64(0))
        let secondClusterPosition = track.count + placeholderCue.count + firstCluster.count
        let data = mkv([
            track,
            cues(timecode: 10, track: 1, clusterPosition: UInt64(secondClusterPosition)),
            firstCluster,
            secondCluster
        ])
        let demuxer = MatroskaDemuxer(source: DataBackedByteSource(data: data))

        _ = try await demuxer.open()
        try await demuxer.seek(to: CMTime(seconds: 0.010, preferredTimescale: 1000))
        let packet = try await demuxer.readNextPacket()

        XCTAssertEqual(packet?.data, Data([0x02]))
    }

    func testDemuxerLoadsSeekHeadCuesOutsideInitialWindowForResume() async throws {
        let info = element([0x15, 0x49, 0xA9, 0x66], payload:
            element([0x44, 0x89], payload: doublePayload(200))
        )
        let track = element([0x16, 0x54, 0xAE, 0x6B], payload: element([0xAE], payload:
            element([0xD7], payload: [0x01]) +
            element([0x83], payload: [0x01]) +
            element([0x86], payload: Array("V_MPEG4/ISO/AVC".utf8))
        ))
        let firstCluster = cluster(timecode: 0, track: 1, payload: [0x01])
        let filler = element([0xEC], payload: Array(repeating: 0, count: 8 * 1024 * 1024))
        let resumeCluster = cluster(timecode: 100, track: 1, payload: [0x02])
        let seekHeadPlaceholder = seekHead(cuesPosition: 0)
        let cuesPlaceholder = cues(timecode: 100, track: 1, clusterPosition: UInt64(0))
        let cuesPosition = info.count + seekHeadPlaceholder.count + track.count + firstCluster.count + filler.count
        let resumeClusterPosition = cuesPosition + cuesPlaceholder.count
        let seekHead = seekHead(cuesPosition: UInt64(cuesPosition))
        let cues = cues(timecode: 100, track: 1, clusterPosition: UInt64(resumeClusterPosition))
        let data = mkv([info, seekHead, track, firstCluster, filler, cues, resumeCluster])
        let source = DataBackedByteSource(data: data)
        let demuxer = MatroskaDemuxer(source: source)

        let stream = try await demuxer.open()
        XCTAssertTrue(stream.seekMap.isSeekable)
        try await demuxer.seek(to: CMTime(seconds: 0.100, preferredTimescale: 1000))
        let packet = try await demuxer.readNextPacket()

        XCTAssertEqual(packet?.data, Data([0x02]))
        let metrics = await source.metrics()
        XCTAssertTrue(metrics.bufferedRanges.contains { $0.offset >= Int64(cuesPosition) })
    }

    func testDemuxerApproximateSeekSkipsInitialClustersWhenCuesAreMissing() async throws {
        let info = element([0x15, 0x49, 0xA9, 0x66], payload:
            element([0x44, 0x89], payload: doublePayload(200))
        )
        let track = element([0x16, 0x54, 0xAE, 0x6B], payload: element([0xAE], payload:
            element([0xD7], payload: [0x01]) +
            element([0x83], payload: [0x01]) +
            element([0x86], payload: Array("V_MPEG4/ISO/AVC".utf8))
        ))
        let firstCluster = cluster(timecode: 0, track: 1, payload: [0x01])
        let filler = element([0xEC], payload: Array(repeating: 0, count: 8 * 1024 * 1024))
        let resumeCluster = cluster(timecode: 100, track: 1, payload: [0x02])
        let data = mkv([info, track, firstCluster, filler, resumeCluster])
        let source = DataBackedByteSource(data: data)
        let demuxer = MatroskaDemuxer(source: source)

        _ = try await demuxer.open()
        try await demuxer.seek(to: CMTime(seconds: 0.100, preferredTimescale: 1000))
        let packet = try await demuxer.readNextPacket()

        XCTAssertEqual(packet?.data, Data([0x02]))
        let metrics = await source.metrics()
        XCTAssertTrue(metrics.bufferedRanges.contains { $0.offset > Int64(1024 * 1024) })
    }

    func testDemuxerApproximateSeekBoundsRequestAtMaximumSourceSize() async throws {
        let info = element([0x15, 0x49, 0xA9, 0x66], payload:
            element([0x44, 0x89], payload: doublePayload(200))
        )
        let track = element([0x16, 0x54, 0xAE, 0x6B], payload: element([0xAE], payload:
            element([0xD7], payload: [0x01]) +
            element([0x83], payload: [0x01]) +
            element([0x86], payload: Array("V_MPEG4/ISO/AVC".utf8))
        ))
        let firstCluster = cluster(timecode: 0, track: 1, payload: [0x01])
        let data = Data(element([0x1A, 0x45, 0xDF, 0xA3], payload: []))
            + Data([0x18, 0x53, 0x80, 0x67, 0xFF])
            + Data(info + track + firstCluster)
        let source = DataBackedByteSource(data: data, advertisedSize: Int64.max)
        let demuxer = MatroskaDemuxer(source: source)

        _ = try await demuxer.open()
        try await demuxer.seek(to: CMTime(seconds: 60, preferredTimescale: 1_000))

        let requests = await source.requests()
        let seekRequest = try XCTUnwrap(requests.last)
        XCTAssertEqual(seekRequest.offset, Int64.max - Int64(8 * 1024 * 1024))
        XCTAssertEqual(seekRequest.length, 8 * 1024 * 1024)
    }

    private func mkv(_ children: [[UInt8]]) -> Data {
        Data(element([0x1A, 0x45, 0xDF, 0xA3], payload: []))
            + Data(element([0x18, 0x53, 0x80, 0x67], payload: children.flatMap { $0 }))
    }

    private func cluster(track: UInt8, payload: [UInt8]) -> [UInt8] {
        cluster(timecode: 0, track: track, payload: payload)
    }

    private func cluster(timecode: UInt8, track: UInt8, payload: [UInt8]) -> [UInt8] {
        let simpleBlock = element([0xA3], payload: [0x80 | track, 0x00, 0x00, 0x80] + payload)
        return element([0x1F, 0x43, 0xB6, 0x75], payload: element([0xE7], payload: [timecode]) + simpleBlock)
    }

    private func cues(timecode: UInt8, track: UInt8, clusterPosition: UInt64) -> [UInt8] {
        let positions = element([0xB7], payload:
            element([0xF7], payload: [track]) +
            element([0xF1], payload: uintPayload(clusterPosition, fixedLength: 8))
        )
        let point = element([0xBB], payload:
            element([0xB3], payload: [timecode]) +
            positions
        )
        return element([0x1C, 0x53, 0xBB, 0x6B], payload: point)
    }

    private func seekHead(cuesPosition: UInt64) -> [UInt8] {
        let seek = element([0x4D, 0xBB], payload:
            element([0x53, 0xAB], payload: [0x1C, 0x53, 0xBB, 0x6B]) +
            element([0x53, 0xAC], payload: uintPayload(cuesPosition, fixedLength: 8))
        )
        return element([0x11, 0x4D, 0x9B, 0x74], payload: seek)
    }

    private func uintPayload(_ value: UInt64, fixedLength: Int? = nil) -> [UInt8] {
        let length = fixedLength ?? max(1, (8 - value.leadingZeroBitCount / 8))
        return (0..<length).map { index in
            let shift = UInt64((length - index - 1) * 8)
            return UInt8((value >> shift) & 0xFF)
        }
    }

    private func element(_ id: [UInt8], payload: [UInt8]) -> [UInt8] {
        id + vintSize(payload.count) + payload
    }

    private func vintSize(_ size: Int) -> [UInt8] {
        precondition(size >= 0)
        let value = UInt64(size)
        for length in 1...8 {
            let maxValue = (UInt64(1) << UInt64(7 * length)) - 2
            guard value <= maxValue else { continue }
            var bytes = Array(repeating: UInt8(0), count: length)
            var remaining = value
            for index in stride(from: length - 1, through: 0, by: -1) {
                bytes[index] = UInt8(remaining & 0xFF)
                remaining >>= 8
            }
            bytes[0] |= UInt8(1 << (8 - length))
            return bytes
        }
        preconditionFailure("EBML test size too large")
    }

    private func doublePayload(_ value: Double) -> [UInt8] {
        withUnsafeBytes(of: value.bitPattern.bigEndian, Array.init)
    }

    private func assertMatroskaError(
        _ data: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try MatroskaSegmentParser().parse(data: data), file: file, line: line) { error in
            XCTAssertTrue(error is EBMLError, "Expected EBMLError, got \(error)", file: file, line: line)
        }
    }
}

private actor DataBackedByteSource: MediaByteSource {
    nonisolated let url = URL(fileURLWithPath: "/tmp/reelfin-test.mkv")
    private let data: Data
    private let advertisedSize: Int64?
    private var snapshot = MediaAccessMetrics()
    private var requestedRanges: [ByteRange] = []

    init(data: Data, advertisedSize: Int64? = nil) {
        self.data = data
        self.advertisedSize = advertisedSize
    }

    func read(range: ByteRange) async throws -> Data {
        guard range.offset >= 0, range.length > 0 else { throw MediaAccessError.invalidRange(range) }
        requestedRanges.append(range)
        let start = Int(range.offset)
        guard start < data.count else { return Data() }
        let end = min(data.count, start + range.length)
        snapshot.rangeRequestCount += 1
        snapshot.currentOffset = Int64(end)
        snapshot.bufferedRanges.append(ByteRange(offset: range.offset, length: end - start))
        return Data(data[start..<end])
    }

    func size() async throws -> Int64? {
        advertisedSize ?? Int64(data.count)
    }

    func cancel() async {}

    func metrics() async -> MediaAccessMetrics {
        snapshot
    }

    func requests() -> [ByteRange] {
        requestedRanges
    }
}
