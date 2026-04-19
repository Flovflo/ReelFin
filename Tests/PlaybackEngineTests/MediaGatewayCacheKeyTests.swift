import Foundation
import XCTest
@testable import PlaybackEngine

final class MediaGatewayCacheKeyTests: XCTestCase {
    func testCacheKeyIsStableAcrossEquivalentInputsAndRedactsSecrets() throws {
        let url = URL(string: "https://media.example.com/library/items/123/master.m3u8?api_key=top-secret&container=fmp4&static=true")!
        let headers = [
            "Accept": "application/vnd.apple.mpegurl",
            "Authorization": "Bearer token-123",
            "X-Emby-Token": "header-token"
        ]

        let key = MediaGatewayCacheKey(
            scope: "playback",
            userID: "user-1",
            serverID: "server-1",
            itemID: "item-1",
            sourceID: "source-1",
            routeURL: url,
            routeHeaders: headers,
            audioSignature: "codec=eac3|channels=6|lang=en",
            subtitleSignature: "codec=srt|lang=fr",
            resumeSeconds: 91
        )

        let same = MediaGatewayCacheKey(
            scope: "playback",
            userID: "user-1",
            serverID: "server-1",
            itemID: "item-1",
            sourceID: "source-1",
            routeURL: url,
            routeHeaders: headers,
            audioSignature: "codec=eac3|channels=6|lang=en",
            subtitleSignature: "codec=srt|lang=fr",
            resumeSeconds: 119.9
        )

        XCTAssertEqual(key, same)
        XCTAssertEqual(key.hashValue, same.hashValue)
        XCTAssertEqual(key.resumeBucket, 3)
        XCTAssertEqual(MediaGatewayCacheKey.resumeBucket(for: 119.9), 3)
        XCTAssertEqual(MediaGatewayCacheKey.resumeBucket(for: 120), 4)

        let encoded = try JSONEncoder().encode(key)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertFalse(json.contains("top-secret"))
        XCTAssertFalse(json.contains("token-123"))
        XCTAssertFalse(json.contains("header-token"))
        XCTAssertFalse(json.contains("api_key"))
        XCTAssertFalse(json.contains("Authorization"))
        XCTAssertFalse(json.contains("X-Emby-Token"))

        let decoded = try JSONDecoder().decode(MediaGatewayCacheKey.self, from: encoded)
        XCTAssertEqual(decoded, key)
    }

    func testRouteSignatureChangesWithHeaderFingerprintButKeepsSecretsOut() {
        let url = URL(string: "https://media.example.com/library/items/123/master.m3u8?container=fmp4&static=true")!

        let signatureA = MediaGatewayCacheKey.routeSignature(
            for: url,
            headers: ["Authorization": "Bearer token-a"]
        )
        let signatureB = MediaGatewayCacheKey.routeSignature(
            for: url,
            headers: ["Authorization": "Bearer token-a"]
        )
        let signatureC = MediaGatewayCacheKey.routeSignature(
            for: url,
            headers: ["Authorization": "Bearer token-b"]
        )

        XCTAssertEqual(signatureA, signatureB)
        XCTAssertNotEqual(signatureA, signatureC)
        XCTAssertFalse(signatureA.contains("token-a"))
        XCTAssertFalse(signatureC.contains("token-b"))
    }
}
