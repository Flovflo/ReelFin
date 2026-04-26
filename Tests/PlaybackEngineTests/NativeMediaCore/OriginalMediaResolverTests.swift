import PlaybackEngine
import Shared
import XCTest

final class OriginalMediaResolverTests: XCTestCase {
    func testBuildsStaticOriginalStreamURLWithoutTranscode() throws {
        let resolver = OriginalMediaResolver()
        let config = ServerConfiguration(serverURL: URL(string: "https://jellyfin.example")!)
        let source = MediaSource(
            id: "source-1",
            itemID: "item-1",
            name: "Original",
            container: "mkv",
            supportsDirectPlay: false,
            supportsDirectStream: false
        )

        let result = try resolver.resolve(
            request: OriginalMediaRequest(itemID: "item-1"),
            sources: [source],
            configuration: config,
            session: UserSession(userID: "u", username: "user", token: "secret"),
            nativeConfig: NativePlayerConfig(enabled: true)
        )

        XCTAssertTrue(result.originalMediaRequested)
        XCTAssertFalse(result.serverTranscodeUsed)
        XCTAssertEqual(result.url.path, "/Videos/item-1/stream")
        XCTAssertTrue(result.url.absoluteString.contains("static=true"))
        XCTAssertTrue(result.url.absoluteString.contains("MediaSourceId=source-1"))
        XCTAssertFalse(result.redactedURLDescription.contains("secret"))
    }
}
