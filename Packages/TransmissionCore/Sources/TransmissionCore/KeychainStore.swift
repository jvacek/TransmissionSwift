import Foundation
import Security
import TransmissionRPC

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

    /// Returns `true` if a password entry exists for this profile without
    /// reading the secret data. No decryption occurs, so no permission prompt
    /// is triggered.
    public func hasPassword(for profileID: UUID) -> Bool {
        SecItemCopyMatching(baseQuery(for: profileID) as CFDictionary, nil) == errSecSuccess
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

extension KeychainStore {
    /// Credentials for `profile`, or nil when it has no username (anonymous
    /// access). A missing Keychain entry is an empty password — the app never
    /// stores an empty one, so a username with no password is a valid setup.
    /// A read *failure* throws, so a locked Keychain is never mistaken for a
    /// wrong password.
    public func credentials(for profile: ServerProfile) throws(KeychainError) -> Credentials? {
        guard let username = profile.username, !username.isEmpty else { return nil }
        let password = try password(for: profile.id) ?? ""
        return Credentials(username: username, password: password)
    }
}
