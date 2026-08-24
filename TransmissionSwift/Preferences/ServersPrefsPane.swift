import SwiftUI
import TransmissionCore
import TransmissionRPC

struct ServersPrefsPane: View {
    @Environment(ServerProfileStore.self) private var profileStore

    private enum PaneSelection: Hashable {
        case existing(UUID)
        case new
    }

    @State private var selection: PaneSelection?
    @State private var pendingNew = false

    private let keychain = KeychainStore()

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                serverList
                Divider()
                listFooter
            }
            .frame(minWidth: 200, maxWidth: 240)

            Divider()

            formPane
                .frame(maxWidth: .infinity)
        }
        .frame(minHeight: 420)
        .onAppear {
            if selection == nil, let first = sortedProfiles.first {
                selection = .existing(first.id)
            }
        }
    }

    // MARK: List

    private var serverList: some View {
        let selectionBinding = Binding<PaneSelection?>(
            get: { selection },
            set: { newVal in
                if selection == .new, newVal != .new {
                    pendingNew = false
                }
                selection = newVal
            }
        )
        return List(selection: selectionBinding) {
            ForEach(sortedProfiles) { profile in
                serverRow(profile)
                    .tag(PaneSelection.existing(profile.id))
            }
            if pendingNew {
                Label("New Server", systemImage: "plus.circle")
                    .italic()
                    .foregroundStyle(.secondary)
                    .tag(PaneSelection.new)
            }
        }
        .listStyle(.sidebar)
    }

    /// The profile list with the active profile pinned to the top.
    private var sortedProfiles: [ServerProfile] {
        guard let active = profileStore.activeProfile else { return profileStore.profiles }
        return [active] + profileStore.profiles.filter { $0.id != active.id }
    }

    private func serverRow(_ profile: ServerProfile) -> some View {
        let isActive = profileStore.activeProfile?.id == profile.id
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(profile.label)
                    .fontWeight(isActive ? .semibold : .regular)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
            }
            Text("\(profile.host):\(profile.port)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospaced()
        }
        .contextMenu {
            if !isActive {
                Button("Make Active") { try? profileStore.setActive(profile.id) }
            }
        }
    }

    private var listFooter: some View {
        HStack(spacing: 0) {
            Button {
                pendingNew = true
                selection = .new
            } label: {
                Label("Add Server", systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("Add server")

            Button {
                if case .existing(let id) = selection {
                    try? profileStore.remove(id: id)
                    selection = profileStore.profiles.first.map { .existing($0.id) }
                }
            } label: {
                Label("Remove Server", systemImage: "minus")
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .disabled(!canRemove)
            .help("Remove selected server")

            Button {
                if case .existing(let id) = selection,
                    let copy = try? profileStore.duplicate(id: id)
                {
                    if let pwd = try? keychain.password(for: id), !pwd.isEmpty {
                        try? keychain.setPassword(pwd, for: copy.id)
                    }
                    selection = .existing(copy.id)
                }
            } label: {
                Label("Duplicate Server", systemImage: "square.on.square")
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .disabled(!canRemove)
            .help("Duplicate selected server")

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var canRemove: Bool {
        if case .existing = selection { return true }
        return false
    }

    // MARK: Form

    @ViewBuilder
    private var formPane: some View {
        switch selection {
        case .new:
            ServerProfileForm(
                mode: .create { newID in
                    pendingNew = false
                    selection = .existing(newID)
                },
                onCancel: {
                    pendingNew = false
                    selection = profileStore.profiles.first.map { .existing($0.id) }
                }
            )
        case .existing(let id):
            if let profile = profileStore.profiles.first(where: { $0.id == id }) {
                ServerProfileForm(mode: .edit(profile), onCancel: nil)
                    .id(id)
            } else {
                emptyState
            }
        case nil:
            emptyState
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Server Selected", systemImage: "server.rack")
        } description: {
            Text("Select a server from the list, or click + to add one.")
        }
    }
}

// MARK: - Server profile form

struct ServerProfileForm: View {
    enum Mode {
        case create(onCreate: (UUID) -> Void)
        case edit(ServerProfile)
    }

    @Environment(ServerProfileStore.self) private var profileStore
    @Environment(TorrentStore.self) private var torrentStore

    let mode: Mode
    var onCancel: (() -> Void)?

    @State private var label: String = ""
    @State private var host: String = "localhost"
    @State private var port: Int = 9091
    @State private var rpcPath: String = "/transmission/rpc"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var hasStoredPassword: Bool = false
    @State private var useHTTPS: Bool = false
    @State private var mappings: [OpenMapping] = []
    @State private var isTesting = false
    @State private var testResultMessage: String?
    @State private var testResultIsFailure = false
    @State private var saveError: String?

    private let keychain = KeychainStore()

    var body: some View {
        Form {
            Section("Connection") {
                TextField("Label", text: $label, prompt: Text("Home NAS"))
                TextField("Host", text: $host)
                TextField("Port", value: $port, format: .number.grouping(.never))
                TextField("RPC Path", text: $rpcPath)
                Toggle("Use HTTPS", isOn: $useHTTPS)
            }

            Section("Authentication") {
                TextField("Username", text: $username, prompt: Text("optional"))
                SecureField(
                    "Password",
                    text: $password,
                    prompt: Text(
                        hasStoredPassword && password.isEmpty ? "Leave blank to keep" : "optional"
                    )
                )
            }

            Section("File Mappings") {
                OpenMappingEditor(
                    mappings: $mappings,
                    sampleServer: sampleServer,
                    sampleTorrent: sampleTorrent,
                    samplePassword: password,
                    resolveSamplePassword: { effectiveSamplePassword() },
                    sampleDownloadDir: torrentStore.downloadDirectory)
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .onAppear { loadFromMode() }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Button("Test Connection") {
                    Task { await runConnectionTest() }
                }
                .disabled(isTesting || host.isEmpty)
                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                }
                if let msg = testResultMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(testResultIsFailure ? AnyShapeStyle(.red) : AnyShapeStyle(.green))
                } else if let err = saveError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Spacer()
                if isCreating, let cancel = onCancel {
                    Button("Cancel", action: cancel)
                        .keyboardShortcut(.cancelAction)
                }
                Button(isCreating ? "Add Server" : "Save Changes") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(host.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
    }

    private func runConnectionTest() async {
        isTesting = true
        testResultMessage = nil
        defer { isTesting = false }

        var components = URLComponents()
        components.scheme = useHTTPS ? "https" : "http"
        components.host = host
        components.port = port
        components.path = rpcPath.hasPrefix("/") ? rpcPath : "/" + rpcPath
        guard let rpcURL = components.url else {
            testResultIsFailure = true
            testResultMessage = "Invalid URL"
            return
        }

        var credentials: Credentials?
        if !username.isEmpty {
            let pwd: String
            if !password.isEmpty {
                pwd = password
            } else if case .edit(let profile) = mode {
                pwd = (try? keychain.password(for: profile.id)) ?? ""
            } else {
                pwd = ""
            }
            if !pwd.isEmpty {
                credentials = Credentials(username: username, password: pwd)
            }
        }

        let client = URLSessionTransmissionClient(rpcURL: rpcURL, credentials: credentials)
        do {
            let info = try await client.sessionGet()
            testResultIsFailure = false
            testResultMessage = "Connected · Transmission \(info.version) (RPC \(info.rpcVersion))"
        } catch {
            testResultIsFailure = true
            testResultMessage = error.localizedDescription
        }
    }

    private var isCreating: Bool {
        if case .create = mode { return true }
        return false
    }

    /// Server-shaped context from the current form fields, used to preview
    /// mappings against a sample torrent.
    private var sampleServer: ServerProfile {
        ServerProfile(
            label: "",
            host: host,
            port: port,
            username: username.isEmpty ? nil : username)
    }

    /// The torrent the mapping preview/Test acts on: the one currently in the
    /// inspector, else the first in the full list. Nil when there are none.
    private var sampleTorrent: Torrent? {
        torrentStore.inspectorDetail ?? torrentStore.torrents.first
    }

    /// Password the mapping Test uses: the typed field if filled, else the
    /// stored Keychain secret (the form field intentionally stays blank for
    /// existing profiles). Resolved on demand so the Keychain isn't read
    /// during rendering.
    private func effectiveSamplePassword() -> String {
        if !password.isEmpty { return password }
        if case .edit(let profile) = mode {
            return (try? keychain.password(for: profile.id)) ?? ""
        }
        return ""
    }

    private func loadFromMode() {
        guard case .edit(let profile) = mode else { return }
        label = profile.label
        host = profile.host
        port = profile.port
        rpcPath = profile.rpcPath
        username = profile.username ?? ""
        useHTTPS = profile.useHTTPS
        mappings = profile.mappings
        hasStoredPassword = keychain.hasPassword(for: profile.id)
        // password field starts empty — keychain secret is never read on load
    }

    private func save() {
        switch mode {
        case .create(let onCreate):
            let profile = ServerProfile(
                label: label.isEmpty ? host : label,
                host: host,
                port: port,
                rpcPath: rpcPath,
                username: username.isEmpty ? nil : username,
                useHTTPS: useHTTPS,
                mappings: mappings
            )
            do {
                if !password.isEmpty { try keychain.setPassword(password, for: profile.id) }
                try profileStore.add(profile)
                onCreate(profile.id)
            } catch {
                saveError = error.localizedDescription
            }

        case .edit(var profile):
            profile.label = label.isEmpty ? host : label
            profile.host = host
            profile.port = port
            profile.rpcPath = rpcPath
            profile.username = username.isEmpty ? nil : username
            profile.useHTTPS = useHTTPS
            profile.mappings = mappings
            do {
                if !password.isEmpty { try keychain.setPassword(password, for: profile.id) }
                try profileStore.update(profile)
            } catch {
                saveError = error.localizedDescription
            }
        }
    }
}

#Preview("Servers") {
    ServersPrefsPane()
        .environment(prefsPreviewProfileStore)
        .environment(prefsPreviewStore)
        .frame(width: 700, height: 480)
}
