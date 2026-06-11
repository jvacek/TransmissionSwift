import SwiftUI
import TransmissionCore
import TransmissionRPC

struct ContentView: View {
    @Environment(ServerProfileStore.self) private var profileStore
    @Environment(TorrentStore.self) private var torrentStore
    @Environment(\.scenePhase) private var scenePhase
    let mockMode: Bool

    private let keychain = KeychainStore()

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
            if new == .background {
                torrentStore.pausePolling()
            } else if new == .active {
                torrentStore.resumePolling()
            }
        }
    }

    @MainActor
    private func connectToProfile(_ profile: ServerProfile) async {
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
    }
}
