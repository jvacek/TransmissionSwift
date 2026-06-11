import SwiftUI
import TransmissionCore
import TransmissionRPC

struct ContentView: View {
    @Environment(ServerProfileStore.self) private var profileStore
    @Environment(TorrentStore.self) private var torrentStore
    let mockMode: Bool

    private let keychain = KeychainStore()

    var body: some View {
        if mockMode {
            MainWindow(mockMode: mockMode)
        } else if profileStore.activeProfile != nil {
            MainWindow(mockMode: false)
                .task(id: profileStore.activeProfile?.id) {
                    guard let profile = profileStore.activeProfile else { return }
                    connectToProfile(profile)
                }
        } else {
            AddServerForm()
                .frame(minWidth: 420, minHeight: 320)
        }
    }

    @MainActor
    private func connectToProfile(_ profile: ServerProfile) {
        guard let rpcURL = profile.rpcURL else {
            torrentStore.setConnectionFailed(reason: "Invalid server URL")
            return
        }
        var credentials: Credentials?
        if let username = profile.username, !username.isEmpty {
            let password = (try? keychain.password(for: profile.id)) ?? ""
            credentials = Credentials(username: username, password: password)
        }
        let client = URLSessionTransmissionClient(rpcURL: rpcURL, credentials: credentials)
        let service = RPCTorrentService(client: client)
        torrentStore.connect(service: service)
    }
}
