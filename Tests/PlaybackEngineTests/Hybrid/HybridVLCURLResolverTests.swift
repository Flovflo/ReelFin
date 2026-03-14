import XCTest
@testable import PlaybackEngine
@testable import Shared

final class HybridVLCURLResolverTests: XCTestCase {
    private let resolver = HybridVLCURLResolver()
    private let configuration = ServerConfiguration(serverURL: URL(string: "https://jellyfin.example.com")!)
    private let session = UserSession(userID: "user-1", username: "Flo", token: "token-1")

    func testResolve_prefersProvidedDirectURL() {
        let source = makeSource(
            directPlayURL: URL(string: "https://jellyfin.example.com/Videos/item/stream?static=true"),
            directStreamURL: nil,
            transcodeURL: URL(string: "https://jellyfin.example.com/Videos/item/master.m3u8")
        )

        let endpoint = resolver.resolve(source: source, configuration: configuration, session: session)

        XCTAssertEqual(
            endpoint?.url.absoluteString,
            "https://jellyfin.example.com/Videos/item/stream?static=true&api_key=token-1"
        )
        XCTAssertEqual(endpoint?.headers["X-Emby-Token"], "token-1")
    }

    func testResolve_constructsRawStreamWhenServerDidNotProvideDirectURL() {
        let source = makeSource(
            directPlayURL: nil,
            directStreamURL: nil,
            transcodeURL: URL(string: "https://jellyfin.example.com/Videos/item/master.m3u8")
        )

        let endpoint = resolver.resolve(source: source, configuration: configuration, session: session)

        XCTAssertEqual(
            endpoint?.url.absoluteString,
            "https://jellyfin.example.com/Videos/item-1/stream?static=true&MediaSourceId=source-1&api_key=token-1"
        )
        XCTAssertEqual(endpoint?.headers["X-Emby-Token"], "token-1")
    }

    func testResolve_fallsBackToTranscodeWhenDirectCannotBeConstructed() {
        let source = MediaSource(
            id: "",
            itemID: "",
            name: "broken",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: nil,
            directPlayURL: nil,
            transcodeURL: URL(string: "https://jellyfin.example.com/Videos/item/master.m3u8")
        )

        let endpoint = resolver.resolve(source: source, configuration: configuration, session: session)

        XCTAssertEqual(
            endpoint?.url.absoluteString,
            "https://jellyfin.example.com/Videos/item/master.m3u8?api_key=token-1"
        )
    }

    private func makeSource(
        directPlayURL: URL?,
        directStreamURL: URL?,
        transcodeURL: URL?
    ) -> MediaSource {
        MediaSource(
            id: "source-1",
            itemID: "item-1",
            name: "source",
            container: "mkv",
            videoCodec: "hevc",
            audioCodec: "eac3",
            supportsDirectPlay: false,
            supportsDirectStream: false,
            directStreamURL: directStreamURL,
            directPlayURL: directPlayURL,
            transcodeURL: transcodeURL
        )
    }
}
