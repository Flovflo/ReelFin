import Foundation
@testable import PlaybackEngine
import Shared
import XCTest

final class PlaybackLoggingTests: XCTestCase {
    func testShortIdentifierUsesStablePrefix() {
        XCTAssertEqual(AppLogFormat.shortIdentifier("8930e2b5481eeaec213595eda347443b"), "8930e2b5")
        XCTAssertEqual(AppLogFormat.shortIdentifier("short"), "short")
        XCTAssertEqual(AppLogFormat.shortIdentifier(nil), "unknown")
    }

    func testPlaybackLogScopeIncludesSessionItemAndAttempt() {
        let scope = PlaybackSessionController.playbackLogScope(
            sessionID: "8930e2b5-a1b2c3",
            itemID: "8930e2b5481eeaec213595eda347443b",
            attempt: 2
        )

        XCTAssertEqual(scope, "session=8930e2b5-a1b2c3 item=8930e2b5 attempt=2")
    }

    func testSensitiveURLSanitizerRedactsAPIKeysRegardlessOfCase() throws {
        let url = try XCTUnwrap(
            URL(string: "https://example.com/videos/id/master.m3u8?ApiKey=SECRET&api_key=SECRET2&token=SECRET3")
        )

        let sanitized = SensitiveURLSanitizer.logString(for: url)

        XCTAssertFalse(sanitized.contains("SECRET"))
        XCTAssertFalse(sanitized.contains("SECRET2"))
        XCTAssertFalse(sanitized.contains("SECRET3"))
        XCTAssertTrue(sanitized.contains("ApiKey=REDACTED"))
        XCTAssertTrue(sanitized.contains("api_key=REDACTED"))
        XCTAssertTrue(sanitized.contains("token=REDACTED"))
    }

    func testSensitiveURLSanitizerCompactPlaybackLogStringKeepsOnlyUsefulParameters() throws {
        let url = try XCTUnwrap(
            URL(
                string: """
                https://example.com/videos/id/main.m3u8?ApiKey=SECRET&VideoCodec=hevc&AudioCodec=aac&Container=fmp4&DeviceId=device-123&PlaySessionId=session-456&SubtitleMethod=External&TranscodeReasons=ContainerNotSupported,AudioCodecNotSupported
                """
            )
        )

        let compact = SensitiveURLSanitizer.compactLogString(for: url)

        XCTAssertFalse(compact.contains("SECRET"))
        XCTAssertFalse(compact.contains("device-123"))
        XCTAssertFalse(compact.contains("session-456"))
        XCTAssertTrue(compact.contains("videocodec=hevc"))
        XCTAssertTrue(compact.contains("audiocodec=aac"))
        XCTAssertTrue(compact.contains("container=fmp4"))
        XCTAssertTrue(compact.contains("subtitlemethod=External"))
        XCTAssertTrue(compact.contains("transcodereasons=ContainerNotSupported"))
    }
}
