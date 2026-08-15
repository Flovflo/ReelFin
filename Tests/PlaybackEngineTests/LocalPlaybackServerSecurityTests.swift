@testable import PlaybackEngine
import Foundation
import Network
import XCTest

final class LocalPlaybackServerSecurityTests: XCTestCase {
    func testProductionCapacityProvidesOneHundredPercentHeadroomOverMeasuredPeak() {
        XCTAssertEqual(LocalPlaybackServerSecurity.defaultConnectionCapacity, 24)
        let gate = LocalPlaybackConnectionGate(capacity: LocalPlaybackServerSecurity.defaultConnectionCapacity)
        let measuredLegitimateBurst = (0..<12).compactMap { _ in gate.acquire() }

        XCTAssertEqual(measuredLegitimateBurst.count, 12)
        XCTAssertEqual(gate.snapshot.peak, 12)
        XCTAssertEqual(gate.snapshot.rejected, 0)
        measuredLegitimateBurst.forEach { $0.release() }
    }

    func testCapabilityContainsExactlyThirtyTwoRandomBytes() throws {
        let bytes = Data(0..<32)
        let security = try LocalPlaybackServerSecurity(capabilityBytes: bytes)

        XCTAssertEqual(security.capabilityPathComponent.count, 64)
        XCTAssertEqual(
            security.capabilityPathComponent,
            "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
        )
    }

    func testAuthorizationRequiresExactCanonicalSlashDelimitedCapability() throws {
        let current = try LocalPlaybackServerSecurity(capabilityBytes: Data(repeating: 0xAB, count: 32))
        let stale = try LocalPlaybackServerSecurity(capabilityBytes: Data(repeating: 0xCD, count: 32))
        let capability = current.capabilityPathComponent

        XCTAssertEqual(current.authorizedResourcePath(for: "/\(capability)/master.m3u8"), "/master.m3u8")
        XCTAssertEqual(current.authorizedResourcePath(for: "/\(capability)/media"), "/media")

        XCTAssertNil(current.authorizedResourcePath(for: "/master.m3u8"))
        XCTAssertNil(current.authorizedResourcePath(for: "/\(stale.capabilityPathComponent)/master.m3u8"))
        XCTAssertNil(current.authorizedResourcePath(for: "/\(capability)x/master.m3u8"))
        XCTAssertNil(current.authorizedResourcePath(for: "/\(capability)%2Fmaster.m3u8"))
        XCTAssertNil(current.authorizedResourcePath(for: "/\(capability)/%2e%2e/master.m3u8"))
        XCTAssertNil(current.authorizedResourcePath(for: "/\(capability)//master.m3u8"))
        XCTAssertNil(current.authorizedResourcePath(for: "/\(capability)/master.m3u8?token=value"))
    }

    func testLogProjectionContainsOnlyRouteClass() throws {
        let security = try LocalPlaybackServerSecurity(capabilityBytes: Data(repeating: 0xEF, count: 32))
        let rawURL = "http://127.0.0.1:49152/\(security.capabilityPathComponent)/media"
        let projection = LocalPlaybackServerSecurity.logProjection(for: .media)

        XCTAssertEqual(projection, "route=media")
        XCTAssertFalse(projection.contains(security.capabilityPathComponent))
        XCTAssertFalse(projection.contains(rawURL))
        XCTAssertFalse(projection.contains("127.0.0.1"))
    }

    func testLoopbackListenerFactoryRequiresIPv4LoopbackEndpoint() throws {
        let configured = try LocalPlaybackServerSecurity.makeLoopbackListener()
        configured.listener.cancel()

        XCTAssertEqual(
            configured.requiredLocalEndpoint,
            .hostPort(host: "127.0.0.1", port: .any)
        )
    }

    func testConnectionGateRefusesCapacityPlusOneAndReleasesExactlyOnce() {
        let gate = LocalPlaybackConnectionGate(capacity: 2)
        let first = gate.acquire()
        let second = gate.acquire()

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNil(gate.acquire())
        XCTAssertEqual(gate.snapshot, .init(active: 2, peak: 2, rejected: 1))

        first?.release()
        first?.release()
        XCTAssertEqual(gate.snapshot.active, 1, "A lease must release its admission exactly once.")

        second?.release()
        XCTAssertEqual(gate.snapshot, .init(active: 0, peak: 2, rejected: 1))
    }

    func testDisabledAdmissionStillMeasuresPeak() {
        let gate = LocalPlaybackConnectionGate(capacity: nil)
        let leases = (0..<7).compactMap { _ in gate.acquire() }

        XCTAssertEqual(leases.count, 7)
        XCTAssertEqual(gate.snapshot, .init(active: 7, peak: 7, rejected: 0))

        leases.forEach { $0.release() }
        XCTAssertEqual(gate.snapshot.active, 0)
    }
}
