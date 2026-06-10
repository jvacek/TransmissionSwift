import Foundation
import Observation
import TransmissionRPC

/// Builds an RPC client for a profile and runs a connectivity check.
/// State (`isTesting`, `lastResult`) is observable so the UI can render it.
@MainActor
@Observable
public final class ConnectionService {
    public private(set) var isTesting = false
    public private(set) var lastResult: Result<SessionInfo, TransmissionError>?

    private let keychain: KeychainStore

    public init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    @discardableResult
    public func testConnection(to profile: ServerProfile) async -> Result<SessionInfo, TransmissionError> {
        isTesting = true
        defer { isTesting = false }

        let result = await Self.run(profile: profile, keychain: keychain)
        lastResult = result
        return result
    }

    private static func run(
        profile: ServerProfile, keychain: KeychainStore
    ) async -> Result<SessionInfo, TransmissionError> {
        guard let rpcURL = profile.rpcURL else {
            return .failure(.network(URLError(.badURL)))
        }
        var credentials: Credentials?
        if let username = profile.username, !username.isEmpty {
            let password = (try? keychain.password(for: profile.id)) ?? ""
            credentials = Credentials(username: username, password: password)
        }
        let client = URLSessionTransmissionClient(rpcURL: rpcURL, credentials: credentials)
        do {
            return .success(try await client.sessionGet())
        } catch {
            return .failure(error)
        }
    }
}
