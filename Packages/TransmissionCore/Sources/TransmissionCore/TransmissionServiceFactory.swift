import Foundation
import TransmissionRPC

/// Builds a live `TorrentService` for one server profile. This is the single
/// construction path shared by the app's connect flow (`ContentView`) and the
/// App Intents, which run outside the SwiftUI object graph and must stand up
/// their own service.
public enum TransmissionServiceFactory {
    /// Builds a service from an already-resolved credential set. Returns nil
    /// when the profile's host/path don't form a valid RPC URL.
    ///
    /// Callers that read the Keychain on the main thread (the app, to show its
    /// "waiting for keychain" state) resolve credentials themselves and use this
    /// overload.
    public static func make(
        for profile: ServerProfile,
        credentials: Credentials?
    ) -> (any TorrentService)? {
        guard let rpcURL = profile.rpcURL else { return nil }
        let client = URLSessionTransmissionClient(rpcURL: rpcURL, credentials: credentials)
        return RPCTorrentService(client: client)
    }

    /// Convenience for callers with no existing credential resolution (App
    /// Intents): reads the password from the Keychain synchronously.
    public static func make(
        for profile: ServerProfile,
        keychain: KeychainStore = KeychainStore()
    ) -> (any TorrentService)? {
        var credentials: Credentials?
        if let username = profile.username, !username.isEmpty {
            let password = (try? keychain.password(for: profile.id)).flatMap { $0 } ?? ""
            credentials = Credentials(username: username, password: password)
        }
        return make(for: profile, credentials: credentials)
    }
}
