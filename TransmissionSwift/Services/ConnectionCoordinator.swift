import Foundation
import Observation
import TransmissionCore
import TransmissionRPC

/// Owns the app's live-connection flow: resolving credentials, building the
/// service and driving `TorrentStore` plus the shared `AppEnvironment`.
///
/// Dependencies are injected so every branch — skip, already-connected, Keychain
/// failure, invalid URL, success — is unit-testable without a daemon, a real
/// Keychain, or the process-wide `AppEnvironment`.
@MainActor
@Observable
final class ConnectionCoordinator {
    /// Reads a profile's stored password. Throws when the Keychain read fails
    /// (locked, cancelled) — distinct from "no password".
    typealias CredentialReader = @Sendable (ServerProfile) throws -> Credentials?
    /// Builds a service for a profile, or nil when its address is invalid.
    typealias ServiceBuilder = (ServerProfile, Credentials?) -> (any TorrentReading)?

    private let store: TorrentStore
    private let environment: AppEnvironment?
    private let isAuxiliaryProcess: Bool
    private let readCredentials: CredentialReader
    private let makeService: ServiceBuilder
    /// The profile last successfully connected. A window close/reopen leaves the
    /// store connected, so a re-appearance for the same profile must be a no-op
    /// (the poll stream was already resumed by `onAppear`).
    private var connectedProfileID: ServerProfile.ID?

    init(
        store: TorrentStore,
        environment: AppEnvironment? = AppEnvironment.current,
        isAuxiliaryProcess: Bool = AppProcess.isXcodeAuxiliary,
        readCredentials: @escaping CredentialReader = { profile in
            try KeychainStore().credentials(for: profile)
        },
        makeService: @escaping ServiceBuilder = { profile, credentials in
            TransmissionServiceFactory.make(for: profile, credentials: credentials)
        }
    ) {
        self.store = store
        self.environment = environment
        self.isAuxiliaryProcess = isAuxiliaryProcess
        self.readCredentials = readCredentials
        self.makeService = makeService
    }

    /// Connect the store to `profile`: read its Keychain secret off the main
    /// actor, build the service, install it and share it with App Intents.
    func connect(to profile: ServerProfile) async {
        // Skip the launch auto-connect under the test runner / previews — no
        // connection is needed there, and reading the Keychain prompts.
        if isAuxiliaryProcess { return }

        // Window was closed and reopened while already connected to this same
        // profile — onAppear's resumePolling() already restarted the stream.
        if case .connected = store.connection, connectedProfileID == profile.id { return }

        var credentials: Credentials?
        if profile.username?.isEmpty == false {
            // Cancel the mock stream and show "waiting for keychain" before the
            // macOS dialog blocks — prevents the mock from racing back.
            store.beginKeychainWait()
            let readCredentials = self.readCredentials
            let resolved = await Task.detached(priority: .userInitiated) {
                Result { try readCredentials(profile) }
            }.value
            guard !Task.isCancelled else { return }
            switch resolved {
            case .success(let credentialsForProfile):
                credentials = credentialsForProfile
            case .failure:
                // A locked Keychain or cancelled prompt must not look like a
                // wrong password, which is what connecting blank would produce.
                store.setConnectionFailed(
                    reason: "Couldn't read the saved password from the Keychain.")
                return
            }
        }
        guard let service = makeService(profile, credentials) else {
            store.setConnectionFailed(reason: "Invalid server URL")
            return
        }
        store.connect(service: service)
        environment?.setConnected(service, for: profile)
        connectedProfileID = profile.id
    }

    /// Stop sharing the live service with App Intents once the app drops the
    /// connection; otherwise an intent keeps talking to a dead connection.
    func connectionStateChanged(_ state: ConnectionState) {
        if case .disconnected = state {
            environment?.clearConnection()
        }
    }
}
