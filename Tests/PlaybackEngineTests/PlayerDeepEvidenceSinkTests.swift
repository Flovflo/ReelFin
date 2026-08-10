import Foundation
@testable import Shared
import XCTest

final class PlayerDeepEvidenceSinkTests: XCTestCase {
    private let mebibyte = 1_048_576

    func testSinkIsOptInAndUsesProtectedCachesDirectory() throws {
        XCTAssertFalse(PlayerDeepEvidenceSink.isEnabled(environment: [:]))
        XCTAssertTrue(PlayerDeepEvidenceSink.isEnabled(environment: ["REELFIN_PLAYER_DEEP_EVIDENCE": "true"]))

        let caches = URL(fileURLWithPath: "/private/container/Library/Caches", isDirectory: true)
        let url = PlayerDeepEvidenceSink.evidenceFileURL(cachesDirectory: caches)
        XCTAssertEqual(url.path, "/private/container/Library/Caches/ReelFin/Diagnostics/reelfin-player-deep-evidence.jsonl")
        XCTAssertFalse(url.path.contains("/Documents/"))
        XCTAssertTrue(PlayerDeepEvidenceSink.evidenceFileURL().path.contains("/Library/Caches/"))
    }

    func testRecordRejectsInvalidCorrelationsFieldsAndNonFiniteNumbers() throws {
        XCTAssertNil(PlayerDeepEvidenceCategory(rawValue: "raw title\nraw-media-id"))
        XCTAssertThrowsError(
            try PlayerDeepEvidenceRecord(
                event: .firstFrame,
                session: "raw-session\nvalue",
                media: "8930e2b5481eeaec213595eda347443b",
                fields: [.elapsedMilliseconds: .decimal(.nan)]
            )
        )
        XCTAssertThrowsError(
            try PlayerDeepEvidenceRecord(
                event: .firstFrame,
                session: "0123456789abcdef",
                fields: [.videoPackets: .integer(1)]
            )
        )
    }

    func testJSONLUsesOnlyTypedAllowlistedFieldsAndOpaqueCorrelations() throws {
        let fixture = try makeFixture()
        let record = try PlayerDeepEvidenceRecord(
            event: .playbackProof,
            session: "0123456789abcdef",
            media: "fedcba9876543210",
            fields: [
                .width: .integer(3840),
                .height: .integer(2160),
                .codec: .category(.hevc),
                .dolbyVision: .boolean(true),
                .observedBitrate: .integer(123_000_000),
            ]
        )

        XCTAssertEqual(fixture.store.append(record), .written)
        let line = try XCTUnwrap(String(contentsOf: fixture.fileURL, encoding: .utf8).split(separator: "\n").first)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )

        XCTAssertEqual(object["event"] as? String, "playbackProof")
        XCTAssertEqual(object["session"] as? String, "0123456789abcdef")
        XCTAssertEqual(object["media"] as? String, "fedcba9876543210")
        XCTAssertEqual(object["codec"] as? String, "hevc")
        XCTAssertEqual(object["dolbyVision"] as? Bool, true)
        XCTAssertNil(object["message"])
        XCTAssertNil(object["title"])
        XCTAssertNil(object["item"])
        XCTAssertFalse(String(line).contains("8930e2b5481eeaec213595eda347443b"))
    }

    func testCreatesOwnerOnlyProtectedDirectoryAndFile() throws {
        let fixture = try makeFixture()
        XCTAssertEqual(fixture.store.append(try sampleTick(session: "0123456789abcdef", current: 1)), .written)

        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: fixture.fileURL.deletingLastPathComponent().path)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fixture.fileURL.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(PlayerDeepEvidenceSink.fileProtection, .complete)
        if let actualProtection = fileAttributes[.protectionKey] as? FileProtectionType {
            XCTAssertEqual(actualProtection, .complete)
        }
    }

    func testPreappendRolloverKeepsExactTotalCeilingAndRejectsOversizedRecord() throws {
        let fixture = try makeFixture(maxBytes: 430)
        var wrote = 0
        for index in 0 ..< 20 {
            XCTAssertEqual(fixture.store.append(try sampleTick(session: "0123456789abcdef", current: Double(index))), .written)
            let size = try XCTUnwrap(
                (FileManager.default.attributesOfItem(atPath: fixture.fileURL.path)[.size] as? NSNumber)?.intValue
            )
            XCTAssertLessThanOrEqual(size, 430)
            wrote += 1
        }
        XCTAssertEqual(wrote, 20)

        let tiny = try makeFixture(maxBytes: 32)
        XCTAssertEqual(tiny.store.append(try sampleTick(session: "0123456789abcdef", current: 1)), .rejectedOversized)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tiny.fileURL.path))
    }

    func testResetIsDeterministicAndConcurrentAppendsRemainValidJSONL() throws {
        let fixture = try makeFixture(maxBytes: mebibyte)
        try FileManager.default.createDirectory(at: fixture.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("raw-old-evidence\n".utf8).write(to: fixture.fileURL)
        let resettingStore = PlayerDeepEvidenceStore(
            fileURL: fixture.fileURL,
            enabled: true,
            maxBytes: mebibyte,
            resetOnFirstAppend: true
        )

        DispatchQueue.concurrentPerform(iterations: 100) { index in
            let record = try! self.sampleTick(
                session: String(format: "%016x", index + 1),
                current: Double(index)
            )
            XCTAssertEqual(resettingStore.append(record), .written)
        }

        let data = try Data(contentsOf: fixture.fileURL)
        XCTAssertLessThanOrEqual(data.count, mebibyte)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("raw-old-evidence"))
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 100)
        for line in lines {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(line.utf8)))
        }
    }

    func testEveryEventHasAClosedSchema() throws {
        XCTAssertEqual(
            Set(PlayerDeepEvidenceEvent.allCases),
            Set([.plan, .routeSelection, .audioSelection, .firstFrame, .ttff, .avPlayerTick, .playbackProof, .sampleBufferTick])
        )
    }

    private func makeFixture(maxBytes: Int = 1_048_576) throws -> (store: PlayerDeepEvidenceStore, fileURL: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayerDeepEvidenceSinkTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("ReelFin/Diagnostics/reelfin-player-deep-evidence.jsonl")
        return (
            PlayerDeepEvidenceStore(fileURL: fileURL, enabled: true, maxBytes: maxBytes, resetOnFirstAppend: false),
            fileURL
        )
    }

    private func sampleTick(session: String, current: Double) throws -> PlayerDeepEvidenceRecord {
        try PlayerDeepEvidenceRecord(
            event: .avPlayerTick,
            session: session,
            media: "fedcba9876543210",
            fields: [
                .currentSeconds: .decimal(current),
                .deltaSeconds: .decimal(1),
                .rate: .decimal(1),
                .timeControl: .category(.playing),
                .likelyToKeepUp: .boolean(true),
                .bufferedSeconds: .decimal(24),
                .droppedFrames: .integer(0),
            ]
        )
    }
}
