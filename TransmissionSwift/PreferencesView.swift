import SwiftUI
import TransmissionCore
import TransmissionRPC

/// The five-pane Preferences window, registered as a `Settings` scene.
///
/// `pendingNavTab` is written by any "Server Settings…" call-site before
/// invoking `openSettings()` / `showSettingsWindow:`. `onAppear` handles the
/// fresh-open case; `onChange` handles the already-visible case.
struct PreferencesView: View {
    @State private var selectedTab = 0
    @AppStorage("prefsPendingNavTab") private var pendingNavTab: Int = -1

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralPrefsPane()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(0)
            SpeedPrefsPane()
                .tabItem { Label("Speed", systemImage: "tortoise") }
                .tag(1)
            NetworkPrefsPane()
                .tabItem { Label("Network", systemImage: "globe") }
                .tag(2)
            RemotePrefsPane()
                .tabItem { Label("Remote", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(3)
            ServersPrefsPane()
                .tabItem { Label("Servers", systemImage: "server.rack") }
                .tag(4)
        }
        .onAppear {
            guard pendingNavTab >= 0 else { return }
            selectedTab = pendingNavTab
            pendingNavTab = -1
        }
        .onChange(of: pendingNavTab) { _, new in
            guard new >= 0 else { return }
            selectedTab = new
            pendingNavTab = -1
        }
    }
}

// MARK: - General

private struct GeneralPrefsPane: View {
    @AppStorage("showAddDialogBeforeAdding") private var showAddDialog = true
    @AppStorage("startMinimized") private var startMinimized = false
    @AppStorage("badgeAppIcon") private var badgeAppIcon = true
    @AppStorage("confirmRemove") private var confirmRemove = true
    @AppStorage("downloadFolder") private var downloadFolder = "~/Downloads"
    @AppStorage("pollingIntervalSeconds") private var pollingInterval: Double = 5.0
    @AppStorage("freeSpaceIntervalSeconds") private var freeSpaceInterval: Double = 60.0
    @AppStorage("fetchTrackerFavicons") private var fetchFavicons = true
    @Environment(FaviconStore.self) private var favicons

    var body: some View {
        Form {
            Section("Downloads") {
                LabeledContent("Default folder") {
                    Text(downloadFolder)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Toggle("Show dialog before adding a torrent", isOn: $showAddDialog)
                    .disabled(true)
            }
            Section("Connection") {
                LabeledContent("Refresh interval") {
                    HStack {
                        TextField("", value: $pollingInterval, format: .number)
                            .frame(width: 52)
                        Stepper("", value: $pollingInterval, in: 1...60, step: 1)
                            .labelsHidden()
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Free space interval") {
                    HStack {
                        TextField("", value: $freeSpaceInterval, format: .number)
                            .frame(width: 52)
                        Stepper("", value: $freeSpaceInterval, in: 10...3600, step: 10)
                            .labelsHidden()
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Sidebar") {
                Toggle("Fetch tracker favicons", isOn: $fetchFavicons)
                    .onChange(of: fetchFavicons) { _, newValue in
                        favicons.setEnabled(newValue)
                    }
            }
            Section("Application") {
                Toggle("Badge app icon with active count", isOn: $badgeAppIcon)
                Toggle("Start minimized", isOn: $startMinimized)
                Toggle("Confirm before removing", isOn: $confirmRemove)
            }
            .disabled(true)
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}

// MARK: - Speed

private struct SpeedPrefsPane: View {
    @AppStorage("globalDownLimitEnabled") private var downLimitEnabled = false
    @AppStorage("globalDownLimitKBps") private var downLimitKBps = 1000
    @AppStorage("globalUpLimitEnabled") private var upLimitEnabled = false
    @AppStorage("globalUpLimitKBps") private var upLimitKBps = 100

    // Turtle (alt-speed) schedule
    @AppStorage("turtleScheduleEnabled") private var turtleScheduleEnabled = false
    @AppStorage("turtleDownLimitKBps") private var turtleDown = 50
    @AppStorage("turtleUpLimitKBps") private var turtleUp = 10
    @AppStorage("turtleScheduleDays") private var turtleDaysMask: Int = 0b0111110  // M–F

    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        Form {
            Section("Global Limits") {
                HStack {
                    Toggle("Download limit", isOn: $downLimitEnabled)
                        .frame(maxWidth: 160, alignment: .leading)
                    if downLimitEnabled {
                        Stepper(value: $downLimitKBps, in: 1...100_000, step: 10) {
                            TextField("", value: $downLimitKBps, format: .number)
                                .frame(width: 70)
                        }
                        Text("KB/s").foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Toggle("Upload limit", isOn: $upLimitEnabled)
                        .frame(maxWidth: 160, alignment: .leading)
                    if upLimitEnabled {
                        Stepper(value: $upLimitKBps, in: 1...100_000, step: 10) {
                            TextField("", value: $upLimitKBps, format: .number)
                                .frame(width: 70)
                        }
                        Text("KB/s").foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(true)

            Section {
                Toggle("Enable turtle mode schedule", isOn: $turtleScheduleEnabled)
                if turtleScheduleEnabled {
                    HStack {
                        Text("Down")
                        Stepper(value: $turtleDown, in: 1...10_000, step: 5) {
                            TextField("", value: $turtleDown, format: .number)
                                .frame(width: 60)
                        }
                        Text("KB/s").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Up")
                        Stepper(value: $turtleUp, in: 1...10_000, step: 5) {
                            TextField("", value: $turtleUp, format: .number)
                                .frame(width: 60)
                        }
                        Text("KB/s").foregroundStyle(.secondary)
                    }
                    LabeledContent("Active days") {
                        HStack(spacing: 4) {
                            ForEach(0..<7) { day in
                                let bit = 1 << day
                                Toggle(
                                    weekdays[day],
                                    isOn: Binding(
                                        get: { turtleDaysMask & bit != 0 },
                                        set: { on in
                                            if on { turtleDaysMask |= bit } else { turtleDaysMask &= ~bit }
                                        }
                                    )
                                )
                                .toggleStyle(.button)
                                .controlSize(.mini)
                            }
                        }
                    }
                }
            } header: {
                Text("Turtle Schedule")
            }
            .disabled(true)
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}

// MARK: - Network

private struct NetworkPrefsPane: View {
    @AppStorage("peerPort") private var peerPort = 51413
    @AppStorage("randomPortOnLaunch") private var randomPort = false
    @AppStorage("portForwardingEnabled") private var portForwarding = false
    @AppStorage("encryption") private var encryption = 1  // 0=prefer, 1=require, 2=tolerate
    @AppStorage("blocklistEnabled") private var blocklistEnabled = false
    @AppStorage("blocklistURL") private var blocklistURL = ""
    @AppStorage("pexEnabled") private var pexEnabled = true
    @AppStorage("dhtEnabled") private var dhtEnabled = true
    @AppStorage("utpEnabled") private var utpEnabled = true

    var body: some View {
        Form {
            Section("Connections") {
                HStack {
                    LabeledContent("Peer listening port") {
                        TextField("Port", value: $peerPort, format: .number.grouping(.never))
                            .frame(width: 80)
                    }
                }
                Toggle("Pick random port on launch", isOn: $randomPort)
                Toggle("Enable UPnP/NAT-PMP port forwarding", isOn: $portForwarding)
            }
            .disabled(true)
            Section("Privacy") {
                LabeledContent("Encryption") {
                    Picker("", selection: $encryption) {
                        Text("Prefer encrypted").tag(0)
                        Text("Require encrypted").tag(1)
                        Text("Allow unencrypted").tag(2)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }
                Toggle("Enable blocklist", isOn: $blocklistEnabled)
                if blocklistEnabled {
                    TextField("Blocklist URL", text: $blocklistURL)
                        .font(.monospaced(.body)())
                }
            }
            .disabled(true)
            Section("Protocol") {
                Toggle("Enable Peer Exchange (PEX)", isOn: $pexEnabled)
                Toggle("Enable DHT", isOn: $dhtEnabled)
                Toggle("Enable µTP", isOn: $utpEnabled)
            }
            .disabled(true)
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}

// MARK: - Remote

private struct RemotePrefsPane: View {
    @AppStorage("remoteAccessEnabled") private var remoteEnabled = false
    @AppStorage("remotePort") private var remotePort = 9091
    @AppStorage("remoteRequireAuth") private var requireAuth = false
    @AppStorage("remoteUsername") private var remoteUsername = ""
    @AppStorage("remoteAllowList") private var allowList = ""

    var body: some View {
        Form {
            Section {
                Toggle("Enable remote access", isOn: $remoteEnabled)
                if remoteEnabled {
                    LabeledContent("Port") {
                        TextField("Port", value: $remotePort, format: .number.grouping(.never))
                            .frame(width: 80)
                    }
                    Toggle("Require authentication", isOn: $requireAuth)
                    if requireAuth {
                        TextField("Username", text: $remoteUsername)
                    }
                    LabeledContent("Allow addresses") {
                        TextField("Comma-separated IPs or *", text: $allowList)
                            .font(.monospaced(.body)())
                    }
                }
            } header: {
                Text("Web Interface")
            } footer: {
                Text(
                    "These settings control the Transmission daemon's built-in web interface — separate from this app's server connections."
                )
                .foregroundStyle(.secondary)
            }
            .disabled(true)
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}

// MARK: - Servers

private struct ServersPrefsPane: View {
    @Environment(ServerProfileStore.self) private var profileStore

    private enum PaneSelection: Hashable {
        case existing(UUID)
        case new
    }

    @State private var selection: PaneSelection?
    @State private var pendingNew = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                serverList
                Divider()
                listFooter
            }
            .frame(width: 200)

            Divider()

            formPane
                .frame(maxWidth: .infinity)
        }
        .frame(width: 660, height: 460)
        .onAppear {
            if selection == nil, let first = profileStore.profiles.first {
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
            ForEach(profileStore.profiles) { profile in
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

    private func loadFromMode() {
        guard case .edit(let profile) = mode else { return }
        label = profile.label
        host = profile.host
        port = profile.port
        rpcPath = profile.rpcPath
        username = profile.username ?? ""
        useHTTPS = profile.useHTTPS
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
                useHTTPS: useHTTPS
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
            do {
                if !password.isEmpty { try keychain.setPassword(password, for: profile.id) }
                try profileStore.update(profile)
            } catch {
                saveError = error.localizedDescription
            }
        }
    }
}
