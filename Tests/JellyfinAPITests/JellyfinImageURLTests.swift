import Foundation
import JellyfinAPI
import Shared
import UIKit
import XCTest

final class JellyfinImageURLTests: XCTestCase {
    func testImageURLDoesNotEmbedAuthenticationToken() async throws {
        let settings = TestSettingsStore(
            serverConfiguration: ServerConfiguration(serverURL: URL(string: "https://example.com")!),
            lastSession: UserSession(userID: "user-1", username: "Flo", token: "")
        )
        let tokenStore = TestTokenStore(storedToken: "secret-token")
        let client = JellyfinAPIClient(tokenStore: tokenStore, settingsStore: settings)

        let generatedURL = await client.imageURL(for: "item-1", type: .primary, width: 640, quality: 80)
        let url = try XCTUnwrap(generatedURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertFalse(url.absoluteString.contains("api_key="))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "format" })?.value, "webp")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "maxWidth" })?.value, "640")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "quality" })?.value, "80")
    }

    func testPrefetchImagesForwardsDeduplicatedPrimaryAndBackdropURLsToImagePipeline() async throws {
        let settings = TestSettingsStore(
            serverConfiguration: ServerConfiguration(serverURL: URL(string: "https://example.com/jellyfin")!),
            lastSession: UserSession(userID: "user-1", username: "Flo", token: "")
        )
        let imagePipeline = PrefetchImagePipelineSpy()
        let client = JellyfinAPIClient(
            tokenStore: TestTokenStore(storedToken: "header-token"),
            settingsStore: settings,
            imagePipeline: imagePipeline
        )
        let items = [
            MediaItem(id: "movie-1", name: "Movie", mediaType: .movie),
            MediaItem(id: "episode-1", name: "Episode", mediaType: .episode, parentID: "series-1"),
            MediaItem(id: "movie-1", name: "Duplicate", mediaType: .movie)
        ]

        await client.prefetchImages(for: items)

        let forwardedURLs = await imagePipeline.forwardedURLs
        XCTAssertEqual(
            Set(forwardedURLs.map(\.absoluteString)),
            Set([
                "https://example.com/jellyfin/Items/movie-1/Images/Primary?format=webp&maxWidth=400&quality=80",
                "https://example.com/jellyfin/Items/movie-1/Images/Backdrop/0?format=webp&maxWidth=1280&quality=72",
                "https://example.com/jellyfin/Items/episode-1/Images/Primary?format=webp&maxWidth=400&quality=80",
                "https://example.com/jellyfin/Items/series-1/Images/Backdrop/0?format=webp&maxWidth=1280&quality=72"
            ])
        )
        XCTAssertEqual(forwardedURLs.count, 4)
    }
}

private actor PrefetchImagePipelineSpy: ImagePipelineProtocol {
    private(set) var forwardedURLs: [URL] = []

    func image(for _: URL) async throws -> UIImage {
        throw PrefetchSpyError.unexpectedImageLoad
    }

    func cachedImage(for _: URL) async -> UIImage? { nil }

    func prefetch(urls: [URL]) async {
        forwardedURLs = urls
    }

    nonisolated func cancel(url _: URL) {}

    private enum PrefetchSpyError: Error {
        case unexpectedImageLoad
    }
}

private final class TestSettingsStore: SettingsStoreProtocol, @unchecked Sendable {
    var serverConfiguration: ServerConfiguration?
    var lastSession: UserSession?
    var episodeReleaseNotificationsEnabled = false
    var hasCompletedOnboarding = false
    var completedOnboardingVersion = 0
    var useCustomPlayerEngine = false

    init(serverConfiguration: ServerConfiguration?, lastSession: UserSession?) {
        self.serverConfiguration = serverConfiguration
        self.lastSession = lastSession
    }
}

private final class TestTokenStore: TokenStoreProtocol, @unchecked Sendable {
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
