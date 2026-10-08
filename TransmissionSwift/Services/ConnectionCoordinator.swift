import Foundation
import TransmissionCore
import TransmissionRPC

/// Owns the app's live-connection flow: resolving credentials, building the
/// service and driving `TorrentStore` plus the shared `AppEnvironment`.
///
/// Extracted from `ContentView` so the view no longer owns Keychain reads,
/// service construction or the connection state machine. The view's job is
/// reduced to "profile changed, ask the coordinator" and "connection state
/// changed, tell the coordinator".
@MainActor
final class ConnectionCoordinator {
    private let store: TorrentStore
    private let keychain: KeychainStore
    /// The profile last successfully connected. A window close/reopen leaves the
    /// store connected, so a re-appearance for the same profile must be a no-op
    /// (the poll stream was already resumed by `onAppear`).
    private var connectedProfileID: ServerProfile.ID?

    init(store: TorrentStore, keychain: KeychainStore = KeychainStore()) {
        self.store = store
        self.keychain = keychain
    }

    /// Connect the store to `profile`: read its Keychain secret off the main
    /// actor, build the service, install it and share it with App Intents.
    func connect(to profile: ServerProfile) async {
        // Skip the launch auto-connect under the test runner / previews — no
        // connection is needed there, and reading the Keychain prompts.
        if AppProcess.isXcodeAuxiliary { return }

        // Window was closed and reopened while already connected to this same
        // profile — onAppear's resumePolling() already restarted the stream.
        if case .connected = store.connection, connectedProfileID == profile.id { return }

        var credentials: Credentials?
        if profile.username?.isEmpty == false {
            // Cancel the mock stream and show "waiting for keychain" before the
            // macOS dialog blocks — prevents the mock from racing back.
            store.beginKeychainWait()
            let keychain = self.keychain
            let resolved = await Task.detached(priority: .userInitiated) {
                Result { try keychain.credentials(for: profile) }
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
        guard let service = TransmissionServiceFactory.make(for: profile, credentials: credentials)
        else {
            store.setConnectionFailed(reason: "Invalid server URL")
            return
        }
        store.connect(service: service)
        AppEnvironment.current?.setConnected(service, for: profile)
        connectedProfileID = profile.id
    }

    /// Stop sharing the live service with App Intents once the app drops the
    /// connection; otherwise an intent keeps talking to a dead connection.
    func connectionStateChanged(_ state: ConnectionState) {
        if case .disconnected = state {
            AppEnvironment.current?.clearConnection()
        }
    }
}
