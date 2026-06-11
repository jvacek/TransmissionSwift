import SwiftUI
import TransmissionCore
import TransmissionRPC

struct ContentView: View {
    @Environment(ServerProfileStore.self) private var profileStore
    @Environment(TorrentStore.self) private var torrentStore
    @Environment(\.scenePhase) private var scenePhase
    let mockMode: Bool

    private let keychain = KeychainStore()
    @State private var hasAppeared = false
    @State private var connectedProfileID: ServerProfile.ID?

    var body: some View {
        Group {
            if mockMode {
                MainWindow(mockMode: mockMode)
            } else if profileStore.activeProfile != nil {
                MainWindow(mockMode: false)
                    .task(id: profileStore.activeProfile?.id) {
                        guard let profile = profileStore.activeProfile else { return }
                        await connectToProfile(profile)
                    }
            } else {
                AddServerForm()
                    .frame(minWidth: 420, minHeight: 320)
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

    @MainActor
    private func connectToProfile(_ profile: ServerProfile) async {
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
