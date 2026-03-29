@testable import JellyfinAPI
import XCTest

final class JellyfinDTODecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

    // MARK: - ItemsResponseDTO

    func testItemsResponseDecodes_normalPayload() throws {
        let json = """
        {
            "Items": [
                {
                    "Id": "abc123",
                    "Name": "Test Movie",
                    "Type": "Movie",
                    "ProductionYear": 2024
                }
            ],
            "TotalRecordCount": 1
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(ItemsResponseDTO.self, from: json)
        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(response.items[0].id, "abc123")
        XCTAssertEqual(response.items[0].name, "Test Movie")
    }

    func testItemsResponseDecodes_nullItems() throws {
        let json = """
        {
            "Items": null,
            "TotalRecordCount": 0
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(ItemsResponseDTO.self, from: json)
        XCTAssertEqual(response.items.count, 0, "Null Items should decode as empty array")
    }

    func testItemsResponseDecodes_missingItemsKey() throws {
        let json = """
        {
            "TotalRecordCount": 0
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(ItemsResponseDTO.self, from: json)
        XCTAssertEqual(response.items.count, 0, "Missing Items key should decode as empty array")
    }

    func testItemsResponseDecodes_skipsInvalidItems() throws {
        let json = """
        {
            "Items": [
                {"Id": "good-1", "Name": "Good Movie"},
                {"Id": null, "Name": "Bad Item"},
                {"Id": "good-2", "Name": "Another Good Movie"}
            ]
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(ItemsResponseDTO.self, from: json)
        XCTAssertEqual(response.items.count, 2, "Should skip the item with null Id")
        XCTAssertEqual(response.items[0].id, "good-1")
        XCTAssertEqual(response.items[1].id, "good-2")
    }

    // MARK: - ViewsResponseDTO

    func testViewsResponseDecodes_nullItems() throws {
        let json = """
        {
            "Items": null
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(ViewsResponseDTO.self, from: json)
        XCTAssertEqual(response.items.count, 0, "Null Items should decode as empty array")
    }

    // MARK: - PlaybackInfoResponseDTO

    func testPlaybackInfoDecodes_nullMediaSources() throws {
        let json = """
        {
            "MediaSources": null
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(PlaybackInfoResponseDTO.self, from: json)
        XCTAssertEqual(response.mediaSources.count, 0, "Null MediaSources should decode as empty array")
    }

    // MARK: - MediaSegmentDTO

    func testMediaSegmentQueryDecodesOptionalFieldsAndFallsBackToItemID() throws {
        let json = """
        {
            "Items": [
                {
                    "StartTicks": 0,
                    "EndTicks": 300000000,
                    "Type": "Intro"
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(MediaSegmentQueryResultDTO.self, from: json)
        XCTAssertEqual(response.items.count, 1)

        let segments = response.items.compactMap { $0.toDomain(defaultItemID: "episode-1") }
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].itemID, "episode-1")
        XCTAssertEqual(segments[0].type, .intro)
        XCTAssertEqual(segments[0].startTicks, 0)
        XCTAssertEqual(segments[0].endTicks, 300000000)
    }

    // MARK: - ItemDTO field flexibility

    func testItemDTODecodes_withMinimalFields() throws {
        let json = """
        {
            "Id": "item-1",
            "Name": "Movie"
        }
        """.data(using: .utf8)!

        let item = try decoder.decode(ItemDTO.self, from: json)
        XCTAssertEqual(item.id, "item-1")
        XCTAssertEqual(item.name, "Movie")
        XCTAssertNil(item.runTimeTicks)
    }

    func testItemDTODecodes_withUnexpectedExtraFields() throws {
        let json = """
        {
            "Id": "item-1",
            "Name": "Movie",
            "Type": "Movie",
            "SomeNewField": "unexpected",
            "AnotherField": 42,
            "NestedObject": {"key": "value"}
        }
        """.data(using: .utf8)!

        let item = try decoder.decode(ItemDTO.self, from: json)
        XCTAssertEqual(item.id, "item-1")
    }

    // MARK: - Full realistic Jellyfin response

    func testFullNextUpResponse() throws {
        let json = """
        {
            "Items": [
                {
                    "Id": "ep-1",
                    "Name": "Episode 1",
                    "Type": "Episode",
                    "SeriesId": "series-1",
                    "SeriesName": "My Show",
                    "IndexNumber": 1,
                    "ParentIndexNumber": 1,
                    "Overview": "First episode",
                    "RunTimeTicks": 25000000000,
                    "UserData": {
                        "Played": false,
                        "PlaybackPositionTicks": 0,
                        "PlayCount": 0
                    }
                }
            ],
            "TotalRecordCount": 1,
            "StartIndex": 0
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(ItemsResponseDTO.self, from: json)
        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(response.items[0].seriesName, "My Show")
        XCTAssertEqual(response.items[0].userData?.played, false)
    }

    func testEmptyResponseFromServer() throws {
        let json = """
        {
            "Items": [],
            "TotalRecordCount": 0,
            "StartIndex": 0
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(ItemsResponseDTO.self, from: json)
        XCTAssertEqual(response.items.count, 0)
    }

    // MARK: - MediaStreamDTO flexible Bool decoding

    func testMediaStreamDecodes_boolFlagsAsIntegers() throws {
        let json = """
        {
            "Index": 0,
            "Type": "Video",
            "Codec": "hevc",
            "BitDepth": 10,
            "VideoRangeType": "DOVI",
            "DvProfile": 8,
            "DvLevel": 5,
            "RpuPresentFlag": 1,
            "ElPresentFlag": 0,
            "BlPresentFlag": 1,
            "DvBlSignalCompatibilityId": 1,
            "Hdr10PlusPresentFlag": 0,
            "IsDefault": 1,
            "Width": 3840,
            "Height": 2160
        }
        """.data(using: .utf8)!

        let stream = try decoder.decode(MediaStreamDTO.self, from: json)
        XCTAssertEqual(stream.rpuPresentFlag, true, "RpuPresentFlag=1 should decode as true")
        XCTAssertEqual(stream.elPresentFlag, false, "ElPresentFlag=0 should decode as false")
        XCTAssertEqual(stream.blPresentFlag, true, "BlPresentFlag=1 should decode as true")
        XCTAssertEqual(stream.hdr10PlusPresentFlag, false, "Hdr10PlusPresentFlag=0 should decode as false")
        XCTAssertEqual(stream.isDefault, true, "IsDefault=1 should decode as true")
        XCTAssertEqual(stream.dvProfile, 8)
        XCTAssertEqual(stream.width, 3840)
    }

    func testMediaStreamDecodes_boolFlagsAsActualBools() throws {
        let json = """
        {
            "Index": 0,
            "Type": "Video",
            "Codec": "hevc",
            "RpuPresentFlag": true,
            "ElPresentFlag": false,
            "BlPresentFlag": true,
            "IsDefault": false
        }
        """.data(using: .utf8)!

        let stream = try decoder.decode(MediaStreamDTO.self, from: json)
        XCTAssertEqual(stream.rpuPresentFlag, true)
        XCTAssertEqual(stream.elPresentFlag, false)
        XCTAssertEqual(stream.blPresentFlag, true)
        XCTAssertEqual(stream.isDefault, false)
    }

    func testMediaStreamDecodes_missingBoolFlags() throws {
        let json = """
        {
            "Index": 1,
            "Type": "Audio",
            "Codec": "eac3",
            "Channels": 6,
            "ChannelLayout": "5.1"
        }
        """.data(using: .utf8)!

        let stream = try decoder.decode(MediaStreamDTO.self, from: json)
        XCTAssertNil(stream.rpuPresentFlag, "Missing flags should decode as nil")
        XCTAssertNil(stream.elPresentFlag)
        XCTAssertNil(stream.blPresentFlag)
        XCTAssertNil(stream.hdr10PlusPresentFlag)
        XCTAssertEqual(stream.channels, 6)
    }
}
