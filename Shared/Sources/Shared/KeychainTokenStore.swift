import Foundation
import Security

public final class KeychainTokenStore: TokenStoreProtocol, @unchecked Sendable {
    private let service: String
    private let account: String

    public init(service: String = "com.reelfin.auth", account: String = "jellyfin.token") {
        self.service = service
        self.account = account
    }

    public func saveToken(_ token: String) throws {
        let data = Data(token.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
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

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard
            status == errSecSuccess,
            let data = item as? Data,
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

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.persistence("Unable to clear auth token from Keychain.")
        }
    }
}
