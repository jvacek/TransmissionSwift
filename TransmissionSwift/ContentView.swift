import SwiftUI
import TransmissionCore
import TransmissionRPC

struct ContentView: View {
    @Environment(ServerProfileStore.self) private var profileStore
    @Environment(TorrentStore.self) private var torrentStore
    @Environment(\.scenePhase) private var scenePhase
    /// True when replaying a captured snapshot file (`--snapshot`).
    let snapshotMode: Bool

    private let keychain = KeychainStore()
    @State private var hasAppeared = false
    @State private var connectedProfileID: ServerProfile.ID?

    var body: some View {
        Group {
            if snapshotMode {
                // Replay: frozen, read-only state from the snapshot file. No
                // connect task — the service is already the snapshot source.
                MainWindow()
            } else {
                // Always render the main window — when no profile exists it shows
                // a "No Servers" empty state pointing at Settings, so onboarding
                // lives in one window instead of a separate page. The connect task
                // no-ops until a profile is added (id flips from nil to a UUID).
                MainWindow()
                    .task(id: profileStore.activeProfile?.id) {
                        guard let profile = profileStore.activeProfile else { return }
                        await connectToProfile(profile)
                    }
            }
        }
        .onChange(of: scenePhase) { _, new in
            if new == .background || new == .inactive {
                torrentStore.pausePolling()
            } else if new == .active {
                torrentStore.resumePolling()
            }
        }
        .onDisappear { torrentStore.pausePolling() }
        .onAppear {
            if hasAppeared { torrentStore.resumePolling() }
            hasAppeared = true
        }
    }

    /// True when running as Xcode's test-host or preview process. The launch
    /// auto-connect reads the Keychain, and doing that from these freshly
    /// re-signed binaries triggers a keychain authorization prompt even though
    /// nothing user-initiated asked for the password.
    private var isXcodeAuxiliaryProcess: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    @MainActor
    private func connectToProfile(_ profile: ServerProfile) async {
        // Skip the launch auto-connect under the test runner / previews — no
        // connection is needed there, and reading the Keychain prompts.
        if isXcodeAuxiliaryProcess { return }

        // Window was closed and reopened while already connected to this same
        // profile — onAppear's resumePolling() already restarted the stream.
        if case .connected = torrentStore.connection, connectedProfileID == profile.id { return }

        guard let rpcURL = profile.rpcURL else {
            torrentStore.setConnectionFailed(reason: "Invalid server URL")
            return
        }
        var credentials: Credentials?
        if let username = profile.username, !username.isEmpty {
            // Cancel the mock stream and show "waiting for keychain" before
            // the macOS dialog blocks — prevents the mock from racing back.
            torrentStore.beginKeychainWait()
            let profileID = profile.id
            let kc = keychain
            let password = await Task.detached(priority: .userInitiated) {
                (try? kc.password(for: profileID)) ?? ""
            }.value
            guard !Task.isCancelled else { return }
            credentials = Credentials(username: username, password: password)
        }
        let client = URLSessionTransmissionClient(rpcURL: rpcURL, credentials: credentials)
        let service = RPCTorrentService(client: client)
        torrentStore.connect(service: service)
        connectedProfileID = profile.id
    }
}
