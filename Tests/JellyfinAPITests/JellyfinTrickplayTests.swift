@testable import JellyfinAPI
import Shared
import XCTest

final class JellyfinTrickplayTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testItemDTODecodesTrickplayManifest() throws {
        let json = """
        {
            "Id": "episode-1",
            "Name": "Episode 1",
            "Trickplay": {
                "source-1": {
                    "160": {
                        "Width": 160,
                        "Height": 90,
                        "TileWidth": 5,
                        "TileHeight": 5,
                        "ThumbnailCount": 100,
                        "Interval": 1000,
                        "Bandwidth": 128000
                    },
                    "320": {
                        "Width": 320,
                        "Height": 180,
                        "TileWidth": 5,
                        "TileHeight": 5,
                        "ThumbnailCount": 100,
                        "Interval": 1000,
                        "Bandwidth": 256000
                    }
                }
            }
        }
        """.data(using: .utf8)!

        let item = try decoder.decode(ItemDTO.self, from: json)
        let manifest = try XCTUnwrap(
            item.toTrickplayManifest(
                preferredSourceID: "source-1",
                fallbackItemID: "episode-1"
            )
        )

        XCTAssertEqual(manifest.itemID, "episode-1")
        XCTAssertEqual(manifest.sourceID, "source-1")
        XCTAssertEqual(manifest.variants.map(\.width), [160, 320])
    }

    func testItemDTOTrickplayFallsBackToFirstManifestWhenSourceSpecificEntryMissing() throws {
        let json = """
        {
            "Id": "episode-1",
            "Name": "Episode 1",
            "Trickplay": {
                "fallback-source": {
                    "320": {
                        "Width": 320,
                        "Height": 180,
                        "TileWidth": 5,
                        "TileHeight": 4,
                        "ThumbnailCount": 80,
                        "Interval": 1500,
                        "Bandwidth": 256000
                    }
                }
            }
        }
        """.data(using: .utf8)!

        let item = try decoder.decode(ItemDTO.self, from: json)
        let manifest = try XCTUnwrap(
            item.toTrickplayManifest(
                preferredSourceID: "missing-source",
                fallbackItemID: "episode-1"
            )
        )

        XCTAssertEqual(manifest.sourceID, "fallback-source")
        XCTAssertEqual(manifest.variants.first?.intervalMilliseconds, 1_500)
    }

    func testTrickplayTileBaseURLDoesNotEmbedAuthenticationToken() async throws {
        let settings = TrickplayTestSettingsStore(
            serverConfiguration: ServerConfiguration(serverURL: URL(string: "https://example.com")!),
            lastSession: UserSession(userID: "user-1", username: "Flo", token: "")
        )
        let tokenStore = TrickplayTestTokenStore(storedToken: "secret-token")
        let client = JellyfinAPIClient(tokenStore: tokenStore, settingsStore: settings)

        let generatedURL = await client.trickplayTileBaseURL(
            itemID: "episode-1",
            mediaSourceID: "source-1",
            width: 320
        )
        let url = try XCTUnwrap(generatedURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertFalse(url.absoluteString.contains("api_key="))
        XCTAssertEqual(components.path, "/Videos/episode-1/Trickplay/320")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "mediaSourceId" })?.value, "source-1")
    }
}

private final class TrickplayTestSettingsStore: SettingsStoreProtocol, @unchecked Sendable {
    var serverConfiguration: ServerConfiguration?
    var lastSession: UserSession?
    var episodeReleaseNotificationsEnabled = false
    var hasCompletedOnboarding = false
    var completedOnboardingVersion = 0

    init(serverConfiguration: ServerConfiguration?, lastSession: UserSession?) {
        self.serverConfiguration = serverConfiguration
        self.lastSession = lastSession
    }
}

private final class TrickplayTestTokenStore: TokenStoreProtocol, @unchecked Sendable {
    var storedToken: String?

    init(storedToken: String?) {
        self.storedToken = storedToken
    }

    func saveToken(_ token: String) throws {
        storedToken = token
    }

    func fetchToken() throws -> String? {
        storedToken
    }

    func clearToken() throws {
        storedToken = nil
    }
}
