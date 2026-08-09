import Foundation
import Security

struct KeychainSecurityOperations: @unchecked Sendable {
    let update: ([String: Any], [String: Any]) -> OSStatus
    let add: ([String: Any]) -> OSStatus
    let copyMatching: ([String: Any]) -> (OSStatus, Data?)
    let delete: ([String: Any]) -> OSStatus

    static let live = KeychainSecurityOperations(
        update: { query, attributes in
            SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        },
        add: { attributes in
            SecItemAdd(attributes as CFDictionary, nil)
        },
        copyMatching: { query in
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            return (status, item as? Data)
        },
        delete: { query in
            SecItemDelete(query as CFDictionary)
        }
    )
}

public final class KeychainTokenStore: TokenStoreProtocol, @unchecked Sendable {
    private let service: String
    private let account: String
    private let security: KeychainSecurityOperations

    public init(service: String = "com.reelfin.auth", account: String = "jellyfin.token") {
        self.service = service
        self.account = account
        security = .live
    }

    init(service: String, account: String, security: KeychainSecurityOperations) {
        self.service = service
        self.account = account
        self.security = security
    }

    public func saveToken(_ token: String) throws {
        let data = Data(token.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]
        let updateStatus = security.update(query, updateAttributes)

        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw AppError.persistence("Unable to store auth token in Keychain.")
        }

        var addAttributes = query
        addAttributes[kSecValueData as String] = data

        let addStatus = security.add(addAttributes)
        guard addStatus == errSecSuccess else {
            throw AppError.persistence("Unable to store auth token in Keychain.")
        }
    }

    public func fetchToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        let (status, item) = security.copyMatching(query)

        if status == errSecItemNotFound {
            return nil
        }

        guard
            status == errSecSuccess,
            let data = item,
            let token = String(data: data, encoding: .utf8)
        else {
            throw AppError.persistence("Unable to read auth token from Keychain.")
        }

        return token
    }

    public func clearToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = security.delete(query)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.persistence("Unable to clear auth token from Keychain.")
        }
    }
}
