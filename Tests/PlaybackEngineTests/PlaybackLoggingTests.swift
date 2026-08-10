import Foundation
@testable import PlaybackEngine
@testable import Shared
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

    func testSensitiveURLSanitizerProjectsOnlyAllowlistedDiagnosticFields() throws {
        let url = try XCTUnwrap(
            URL(
                string: "HTTPS://alice:password@Example.COM:443/private/library/item.m3u8?opaque_signature=OPAQUE&ToKeN=SECRET&VideoCodec=hevc&videoCODEC=h264&AllowAudioStreamCopy=false&Domain=https%3A%2F%2Fevil.example#private-fragment"
            )
        )

        let sanitized = SensitiveURLSanitizer.logString(for: url)
        let compact = SensitiveURLSanitizer.compactLogString(for: url)

        XCTAssertEqual(compact, sanitized)
        XCTAssertNotNil(
            sanitized.range(
                of: #"^https://example\.com path=[0-9a-f]{12} queryNames=allowaudiostreamcopy,videocodec queryItems=6$"#,
                options: .regularExpression
            )
        )
        for forbidden in [
            "alice", "password", "private", "library", "item.m3u8", "private-fragment",
            "opaque_signature", "OPAQUE", "token", "SECRET", "Domain", "evil.example",
            "hevc", "h264", "false", "@", "?", "#"
        ] {
            XCTAssertFalse(sanitized.localizedCaseInsensitiveContains(forbidden), sanitized)
        }
    }

    func testSensitiveURLSanitizerNormalizesOriginAndPort() throws {
        let defaultHTTP = try XCTUnwrap(URL(string: "http://EXAMPLE.com:80/a"))
        let defaultHTTPS = try XCTUnwrap(URL(string: "https://EXAMPLE.com:443/a"))
        let nondefault = try XCTUnwrap(URL(string: "https://EXAMPLE.com:8443/a"))

        XCTAssertTrue(SensitiveURLSanitizer.logString(for: defaultHTTP).hasPrefix("http://example.com path="))
        XCTAssertTrue(SensitiveURLSanitizer.logString(for: defaultHTTPS).hasPrefix("https://example.com path="))
        XCTAssertTrue(SensitiveURLSanitizer.logString(for: nondefault).hasPrefix("https://example.com:8443 path="))
    }

    func testSensitiveURLSanitizerPathCorrelationIsStableAndPathSpecific() throws {
        let first = try XCTUnwrap(URL(string: "https://example.com/private/item.m3u8?VideoCodec=hevc"))
        let samePath = try XCTUnwrap(URL(string: "https://example.com/private/item.m3u8?VideoCodec=h264&token=other"))
        let otherPath = try XCTUnwrap(URL(string: "https://example.com/private/other.m3u8?VideoCodec=hevc"))

        let firstCorrelation = try pathCorrelation(in: SensitiveURLSanitizer.logString(for: first))
        let samePathCorrelation = try pathCorrelation(in: SensitiveURLSanitizer.logString(for: samePath))
        let otherPathCorrelation = try pathCorrelation(in: SensitiveURLSanitizer.logString(for: otherPath))

        XCTAssertEqual(firstCorrelation, samePathCorrelation)
        XCTAssertNotEqual(firstCorrelation, otherPathCorrelation)
    }

    func testSensitiveURLLogProjectorUsesInjectedHMACKey() throws {
        let projector = SensitiveURLLogProjector(
            keyData: Data((0 ..< 32).map(UInt8.init))
        )
        let url = try XCTUnwrap(
            URL(string: "https://EXAMPLE.com/private/item.m3u8?VideoCodec=hevc&token=SECRET")
        )

        XCTAssertEqual(
            projector.logString(for: url),
            "https://example.com path=edf941fdba1c queryNames=videocodec queryItems=2"
        )
    }

    func testSensitiveURLSanitizerRejectsNonHTTPAndRelativeURLsWithoutRawFallback() throws {
        let relative = try XCTUnwrap(URL(string: "private/path?token=SECRET"))
        let schemeRelative = try XCTUnwrap(URL(string: "//example.com/private?VideoCodec=hevc"))
        let file = URL(fileURLWithPath: "/Users/person/Library/private.m3u8")

        for url in [relative, schemeRelative, file] {
            XCTAssertEqual(SensitiveURLSanitizer.logString(for: url), "invalid-url")
            XCTAssertEqual(SensitiveURLSanitizer.compactLogString(for: url), "invalid-url")
        }
    }

    func testSensitiveURLSanitizerBlocksQueryNameAndValueInjection() throws {
        let url = try XCTUnwrap(
            URL(string: "https://example.com/path?VideoCodec%0Ahost=evil.example&VideoCodec=hevc%0Auserinfo=alice")
        )

        let projection = SensitiveURLSanitizer.logString(for: url)

        XCTAssertNotNil(
            projection.range(
                of: #"^https://example\.com path=[0-9a-f]{12} queryNames=videocodec queryItems=2$"#,
                options: .regularExpression
            )
        )
        XCTAssertFalse(projection.contains("\n"))
        XCTAssertFalse(projection.contains("evil.example"))
        XCTAssertFalse(projection.contains("userinfo"))
        XCTAssertFalse(projection.contains("alice"))
        XCTAssertFalse(projection.contains("hevc"))
    }

    func testSensitiveURLSanitizerPreservesCacheKeyBehaviorByteForByte() throws {
        let url = try XCTUnwrap(
            URL(
                string: "https://User:Pass@EXAMPLE.com:443/private/item?ApiKey=SECRET&VideoCodec=hevc&opaque_signature=OPAQUE#fragment"
            )
        )

        XCTAssertEqual(
            SensitiveURLSanitizer.cacheKey(for: url),
            "https://User:Pass@EXAMPLE.com:443/private/item?VideoCodec=hevc&opaque_signature=OPAQUE#fragment"
        )
    }

    func testPlaylistURILoggingRejectsRelativeAndMalformedInputWithoutRawFallback() {
        let segment = "hls1/private/0.ts?ApiKey=SECRET&VideoCodec=h264"

        let redacted = PlaybackSessionController.redactedPlaylistURIForLog(segment)

        XCTAssertEqual(redacted, "invalid-url")
        XCTAssertEqual(PlaybackSessionController.redactedPlaylistURIForLog("http://["), "invalid-url")
        XCTAssertEqual(PlaybackSessionController.redactedPlaylistURIForLog(nil), "none")
    }

    func testPlaylistURILoggingUsesSharedProjectionForAbsoluteInput() throws {
        let playlist = try XCTUnwrap(
            URL(string: "https://user:pass@example.com/private/main.m3u8?VideoCodec=h264&token=SECRET#fragment")
        )

        XCTAssertEqual(
            PlaybackSessionController.redactedPlaylistURIForLog(playlist.absoluteString),
            SensitiveURLSanitizer.logString(for: playlist)
        )
    }

    func testAssetURLValidatorDoesNotPutUnsupportedURLComponentsInLocalizedError() throws {
        let url = try XCTUnwrap(
            URL(string: "ftp://user:password@example.com/private/item.mkv?token=SECRET#fragment")
        )

        let message = try XCTUnwrap(AssetURLValidator().validate(url: url)?.localizedDescription)

        XCTAssertEqual(message, "Unsupported playback URL for AVFoundation: invalid-url")
    }

    func testNativeRouteViolationsDoNotExposePathOrQueryValues() throws {
        let url = try XCTUnwrap(
            URL(
                string: "https://user:password@example.com/private/item/main.m3u8?VideoCodec=h264&TranscodeReasons=PRIVATE&token=SECRET#fragment"
            )
        )

        let messages = NativePlayerRouteGuard.validateOriginalPlaybackURL(url).map(\.localizedDescription)
        let combined = messages.joined(separator: " ")

        XCTAssertEqual(messages.count, 3)
        XCTAssertTrue(combined.contains("https://example.com path="))
        XCTAssertTrue(combined.contains("videocodec"))
        XCTAssertTrue(combined.contains("transcodereasons"))
        for forbidden in ["user", "password", "/private/item/main.m3u8", "h264", "PRIVATE", "SECRET", "token", "?", "#", "@"] {
            XCTAssertFalse(combined.localizedCaseInsensitiveContains(forbidden), combined)
        }
    }

    func testTrackSelectionLogsCannotEmitRawIDsURLsHeadersOrTokens() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("PlaybackEngine/Sources/PlaybackEngine/PlaybackSessionController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let selectionLogBlocks = lines.indices.compactMap { index -> String? in
            guard lines[index].contains("nativeplayer.audio.selection_changed")
                    || lines[index].contains("nativeplayer.subtitle.selection_changed") else {
                return nil
            }
            let end = min(lines.index(index, offsetBy: 4, limitedBy: lines.endIndex) ?? lines.endIndex, lines.endIndex)
            return lines[index..<end].joined(separator: "\n")
        }

        XCTAssertEqual(selectionLogBlocks.count, 2)
        for block in selectionLogBlocks {
            let lowered = block.lowercased()
            XCTAssertFalse(lowered.contains(" id="))
            XCTAssertFalse(lowered.contains("track.id"))
            XCTAssertFalse(lowered.contains("url"))
            XCTAssertFalse(lowered.contains("header"))
            XCTAssertFalse(lowered.contains("token"))
            XCTAssertFalse(lowered.contains("api_key"))
        }
    }

    private func pathCorrelation(in projection: String) throws -> String {
        let expression = try NSRegularExpression(pattern: #" path=([0-9a-f]{12}) "#)
        let range = NSRange(projection.startIndex..<projection.endIndex, in: projection)
        let match = try XCTUnwrap(expression.firstMatch(in: projection, range: range))
        let correlationRange = try XCTUnwrap(Range(match.range(at: 1), in: projection))
        return String(projection[correlationRange])
    }
}
