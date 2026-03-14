import XCTest
@testable import PlaybackEngine

final class PlaybackLogSanitizerTests: XCTestCase {
    func testSanitizeRedactsAPIKeyButPreservesStructure() {
        let url = URL(
            string: "https://example.com/Videos/id/master.m3u8?Container=fmp4&api_key=secret-token&AudioCodec=aac"
        )!

        let sanitized = PlaybackLogSanitizer.sanitize(url)

        XCTAssertTrue(sanitized.contains("Container=fmp4"))
        XCTAssertTrue(sanitized.contains("AudioCodec=aac"))
        XCTAssertTrue(sanitized.contains("api_key=REDACTED"))
        XCTAssertFalse(sanitized.contains("secret-token"))
    }
}
