import Foundation
import Security
@testable import Shared
import XCTest

final class KeychainTokenStoreTests: XCTestCase {
    func testExistingTokenSurvivesUpdateFailureWithoutDeleteOrAdd() throws {
        let security = InMemoryKeychainSecurity(storedToken: "old-synthetic-token")
        security.forcedUpdateStatus = errSecInteractionNotAllowed
        let store = makeStore(security: security)

        XCTAssertThrowsError(try store.saveToken("new-synthetic-token"))

        XCTAssertEqual(security.updateCallCount, 1)
        XCTAssertEqual(security.addCallCount, 0)
        XCTAssertEqual(security.deleteCallCount, 0)
        XCTAssertEqual(try store.fetchToken(), "old-synthetic-token")
    }

    func testMissingTokenFallsBackFromUpdateToAdd() throws {
        let security = InMemoryKeychainSecurity(storedToken: nil)
        let store = makeStore(security: security)

        try store.saveToken("new-synthetic-token")

        XCTAssertEqual(security.updateCallCount, 1)
        XCTAssertEqual(security.addCallCount, 1)
        XCTAssertEqual(security.deleteCallCount, 0)
        XCTAssertEqual(try store.fetchToken(), "new-synthetic-token")
    }

    func testExistingTokenUpdatesValueWithoutAddOrDelete() throws {
        let security = InMemoryKeychainSecurity(storedToken: "old-synthetic-token")
        let store = makeStore(security: security)

        try store.saveToken("new-synthetic-token")

        XCTAssertEqual(security.updateCallCount, 1)
        XCTAssertEqual(security.addCallCount, 0)
        XCTAssertEqual(security.deleteCallCount, 0)
        XCTAssertEqual(security.lastUpdateAttributeKeys, [kSecValueData as String])
        XCTAssertEqual(try store.fetchToken(), "new-synthetic-token")
    }

    func testFetchAndClearPreserveExistingBehavior() throws {
        let security = InMemoryKeychainSecurity(storedToken: "old-synthetic-token")
        let store = makeStore(security: security)

        XCTAssertEqual(try store.fetchToken(), "old-synthetic-token")
        try store.clearToken()

        XCTAssertNil(try store.fetchToken())
        XCTAssertEqual(security.deleteCallCount, 1)
    }

    private func makeStore(security: InMemoryKeychainSecurity) -> KeychainTokenStore {
        KeychainTokenStore(
            service: "com.reelfin.tests",
            account: "synthetic.token",
            security: security.operations
        )
    }
}

private final class InMemoryKeychainSecurity: @unchecked Sendable {
    var forcedUpdateStatus: OSStatus?
    private(set) var updateCallCount = 0
    private(set) var addCallCount = 0
    private(set) var deleteCallCount = 0
    private(set) var lastUpdateAttributeKeys: Set<String> = []
    private var storedData: Data?

    init(storedToken: String?) {
        storedData = storedToken.map { Data($0.utf8) }
    }

    var operations: KeychainSecurityOperations {
        KeychainSecurityOperations(
            update: { [self] _, attributes in
                updateCallCount += 1
                lastUpdateAttributeKeys = Set(attributes.keys)
                if let forcedUpdateStatus {
                    return forcedUpdateStatus
                }
                guard storedData != nil else {
                    return errSecItemNotFound
                }
                storedData = attributes[kSecValueData as String] as? Data
                return errSecSuccess
            },
            add: { [self] attributes in
                addCallCount += 1
                storedData = attributes[kSecValueData as String] as? Data
                return errSecSuccess
            },
            copyMatching: { [self] _ in
                guard let storedData else {
                    return (errSecItemNotFound, nil)
                }
                return (errSecSuccess, storedData)
            },
            delete: { [self] _ in
                deleteCallCount += 1
                guard storedData != nil else {
                    return errSecItemNotFound
                }
                storedData = nil
                return errSecSuccess
            }
        )
    }
}
