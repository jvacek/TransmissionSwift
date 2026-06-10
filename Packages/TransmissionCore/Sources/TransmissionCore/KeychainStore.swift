import Foundation
import Security

public struct KeychainError: Error, Sendable, Equatable {
    public let status: OSStatus
}

/// Generic-password Keychain items, one per server profile, keyed by the
/// profile's UUID. Service name distinguishes our items from everyone else's.
public struct KeychainStore: Sendable {
    private let service: String

    public init(service: String = "net.jvacek.TransmissionSwift") {
        self.service = service
    }

    private func baseQuery(for profileID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString,
        ]
    }

    public func password(for profileID: UUID) throws(KeychainError) -> String? {
        var query = baseQuery(for: profileID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    public func setPassword(_ password: String, for profileID: UUID) throws(KeychainError) {
        let passwordData = Data(password.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery(for: profileID) as CFDictionary,
            [kSecValueData as String: passwordData] as CFDictionary
        )
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery(for: profileID)
            addQuery[kSecValueData as String] = passwordData
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError(status: addStatus)
            }
        default:
            throw KeychainError(status: updateStatus)
        }
    }

    public func deletePassword(for profileID: UUID) throws(KeychainError) {
        let status = SecItemDelete(baseQuery(for: profileID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}
