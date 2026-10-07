import Foundation
import TransmissionRPC

/// Builds a live `TorrentService` for one server profile. This is the single
/// construction path shared by the app's connect flow and the App Intents, which
/// run outside the SwiftUI object graph and must stand up their own service.
public enum TransmissionServiceFactory {
    /// Why a service couldn't be built for a profile.
    public enum Failure: Error, Sendable, Equatable {
        /// The profile's host/path don't form a valid RPC URL.
        case invalidRPCURL
        /// Reading the stored password failed (locked Keychain, cancelled prompt).
        case keychain(status: OSStatus)
    }

    /// Builds a service from an already-resolved credential set. Returns nil
    /// when the profile's host/path don't form a valid RPC URL.
    ///
    /// Callers that resolve credentials themselves (the app, to show its
    /// "waiting for keychain" state) use this overload.
    public static func make(
        for profile: ServerProfile,
        credentials: Credentials?
    ) -> (any TorrentService)? {
        guard let rpcURL = profile.rpcURL else { return nil }
        let client = URLSessionTransmissionClient(rpcURL: rpcURL, credentials: credentials)
        return RPCTorrentService(client: client)
    }

    /// Builds a service, resolving the password through `passwordProvider`.
    ///
    /// A missing entry means "no password" — the app never stores an empty one,
    /// so a username with an empty password is a valid setup — and is sent as an
    /// empty string. A provider *failure* is not: it throws, so the caller can
    /// report the real cause instead of connecting with a blank password and
    /// surfacing a misleading auth failure.
    static func make(
        for profile: ServerProfile,
        passwordProvider: (UUID) throws(KeychainError) -> String?
    ) throws(Failure) -> any TorrentService {
        var credentials: Credentials?
        if let username = profile.username, !username.isEmpty {
            let password: String
            do {
                password = try passwordProvider(profile.id) ?? ""
            } catch {
                throw Failure.keychain(status: error.status)
            }
            credentials = Credentials(username: username, password: password)
        }
        guard let service = make(for: profile, credentials: credentials) else {
            throw Failure.invalidRPCURL
        }
        return service
    }

    /// Convenience for callers with no existing credential resolution (App
    /// Intents): reads the password from the Keychain synchronously.
    public static func make(
        for profile: ServerProfile,
        keychain: KeychainStore = KeychainStore()
    ) throws(Failure) -> any TorrentService {
        try make(
            for: profile,
            passwordProvider: { (id: UUID) throws(KeychainError) -> String? in
                try keychain.password(for: id)
            })
    }
}
