// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import TransmissionCore
import TransmissionRPC

/// What the server editor sheet is showing: a new profile, or an existing one.
enum ServerEditorTarget: Identifiable {
    case create
    case edit(ServerProfile)

    var id: String {
        switch self {
        case .create: return "new"
        case .edit(let profile): return profile.id.uuidString
        }
    }
}

/// App-wide daemon profiles, listed with the active one first. Editing opens
/// `ServerProfileForm` in a sheet, the same shape as the Mappings pane.
struct ServersPrefsPane: View {
    @Environment(ServerProfileStore.self) private var profileStore

    /// Non-nil while the editor sheet is up.
    @State private var editor: ServerEditorTarget?
    @State private var pendingRemovalID: UUID?
    @State private var actionError: String?

    private let keychain = KeychainStore()

    var body: some View {
        Form {
            Section {
                if profileStore.profiles.isEmpty {
                    Text("No servers yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedProfiles) { profile in
                        serverRow(profile)
                    }
                }

                Button {
                    editor = .create
                } label: {
                    Label("Add Server…", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Servers")
            }
        }
        .formStyle(.grouped)
        .alert(
            "Couldn't Update Servers",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .confirmationDialog(
            "Remove Server?",
            isPresented: Binding(
                get: { pendingRemovalID != nil },
                set: { if !$0 { pendingRemovalID = nil } }
            ),
            presenting: pendingRemovalID
        ) { id in
            Button("Remove", role: .destructive) { removeServer(id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The saved password will be deleted. Torrents on the daemon are not affected.")
        }
        .sheet(item: $editor) { target in
            ServerProfileForm(
                target: target,
                onCancel: { editor = nil },
                onSaved: { editor = nil })
        }
    }

    private func serverRow(_ profile: ServerProfile) -> some View {
        let isActive = profileStore.activeProfile?.id == profile.id
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.label)
                    .fontWeight(isActive ? .semibold : .regular)
                Text("\(profile.host):\(profile.port)")
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
                    .help("Active server")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editor = .edit(profile) }
        .contextMenu {
            if !isActive {
                Button("Make Active") { makeActive(profile.id) }
            }
            Button("Edit…") { editor = .edit(profile) }
            Button("Duplicate") { duplicate(profile.id) }
            Divider()
            Button("Remove…", role: .destructive) { pendingRemovalID = profile.id }
        }
    }

    /// The profile list with the active profile pinned to the top.
    private var sortedProfiles: [ServerProfile] {
        guard let active = profileStore.activeProfile else { return profileStore.profiles }
        return [active] + profileStore.profiles.filter { $0.id != active.id }
    }

    private func makeActive(_ id: UUID) {
        do {
            try profileStore.setActive(id)
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// The copy is meant to work as-is, so it takes the Keychain secret too.
    private func duplicate(_ id: UUID) {
        do {
            guard let copy = try profileStore.duplicate(id: id) else { return }
            if let password = try? keychain.password(for: id), !password.isEmpty {
                try? keychain.setPassword(password, for: copy.id)
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func removeServer(_ id: UUID) {
        do {
            try profileStore.remove(id: id)
            // The profile id is never reused, so an orphaned secret would sit
            // in the Keychain forever.
            try? keychain.deletePassword(for: id)
            Task { await SpotlightIndexer.indexServers(profileStore.profiles) }
        } catch {
            // The store rolled back; the row stays for a retry.
            actionError = error.localizedDescription
        }
    }
}

// MARK: - Server profile editor

struct ServerProfileForm: View {
    let target: ServerEditorTarget
    let onCancel: () -> Void
    let onSaved: () -> Void

    @Environment(ServerProfileStore.self) private var profileStore

    @State private var fields: Fields
    @State private var hasStoredPassword = false
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testFailed = false
    @State private var saveError: String?

    /// The values the sheet opened with, for the unsaved-changes check.
    private let initialFields: Fields
    private let keychain = KeychainStore()

    /// Field state as one value, so "changed since opening" is a comparison.
    private struct Fields: Equatable {
        var label = ""
        var host = ""
        var port = 9091
        var rpcPath = "/transmission/rpc"
        var username = ""
        var password = ""
        var useHTTPS = false

        init() {}

        init(_ profile: ServerProfile) {
            label = profile.label
            host = profile.host
            port = profile.port
            rpcPath = profile.rpcPath
            username = profile.username ?? ""
            useHTTPS = profile.useHTTPS
        }
    }

    init(target: ServerEditorTarget, onCancel: @escaping () -> Void, onSaved: @escaping () -> Void) {
        self.target = target
        self.onCancel = onCancel
        self.onSaved = onSaved
        let initial: Fields =
            switch target {
            case .create: Fields()
            case .edit(let profile): Fields(profile)
            }
        initialFields = initial
        _fields = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isCreating ? "Add Server" : "Edit Server")
                .font(.headline)
                .padding(.horizontal, 20)

            Form {
                Section("Connection") {
                    TextField("Label", text: $fields.label, prompt: Text("Home NAS"))
                    TextField("Host", text: $fields.host, prompt: Text("localhost"))
                        .monospaced()
                    TextField(
                        "Port",
                        value: $fields.port,
                        format: .number.grouping(.never),
                        prompt: Text("9091")
                    )
                    .monospaced()
                    TextField("RPC path", text: $fields.rpcPath, prompt: Text("/transmission/rpc"))
                        .monospaced()
                    Toggle("Use HTTPS", isOn: $fields.useHTTPS)
                }

                Section("Authentication") {
                    TextField("Username", text: $fields.username, prompt: Text("Optional"))
                        .monospaced()
                    SecureField(
                        "Password",
                        text: $fields.password,
                        prompt: Text(hasStoredPassword ? "Leave blank to keep" : "Optional")
                    )
                    .monospaced()
                }
            }
            .formStyle(.grouped)

            SheetButtonRow(
                isCreating ? "Add Server" : "Save",
                canConfirm: canSave,
                onCancel: onCancel,
                onConfirm: save
            ) {
                Button("Test Connection") {
                    Task { await runConnectionTest() }
                }
                .disabled(isTesting || fields.host.isEmpty)
                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                }
                if let status = statusMessage {
                    Text(status.text)
                        .font(.caption)
                        .foregroundStyle(status.failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(status.text)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 20)
        .frame(width: 480, height: 480)
        .onAppear {
            if let profile = editedProfile {
                hasStoredPassword = keychain.hasPassword(for: profile.id)
            }
        }
    }

    private var editedProfile: ServerProfile? {
        if case .edit(let profile) = target { return profile }
        return nil
    }

    private var isCreating: Bool {
        if case .create = target { return true }
        return false
    }

    private var canSave: Bool {
        !fields.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && fields != initialFields
    }

    /// A save error wins over the last connection test's outcome.
    private var statusMessage: (text: String, failed: Bool)? {
        if let saveError { return (saveError, true) }
        if let testMessage { return (testMessage, testFailed) }
        return nil
    }

    private func runConnectionTest() async {
        isTesting = true
        testMessage = nil
        defer { isTesting = false }

        let probe = ServerProfile(
            label: "",
            host: fields.host,
            port: fields.port,
            rpcPath: fields.rpcPath,
            useHTTPS: fields.useHTTPS)
        guard let rpcURL = probe.rpcURL else {
            testFailed = true
            testMessage = "Invalid URL"
            return
        }

        var credentials: Credentials?
        if !fields.username.isEmpty {
            let pwd: String
            if !fields.password.isEmpty {
                pwd = fields.password
            } else if let profile = editedProfile {
                do {
                    pwd = try keychain.password(for: profile.id) ?? ""
                } catch {
                    testFailed = true
                    testMessage = "Couldn't read the saved password from the Keychain."
                    return
                }
            } else {
                pwd = ""
            }
            if !pwd.isEmpty {
                credentials = Credentials(username: fields.username, password: pwd)
            }
        }

        let client = URLSessionTransmissionClient(rpcURL: rpcURL, credentials: credentials)
        do {
            let info = try await client.sessionGet()
            testFailed = false
            testMessage = "Connected · Transmission \(info.version) (RPC \(info.rpcVersion))"
        } catch {
            testFailed = true
            testMessage = error.localizedDescription
        }
    }

    private func save() {
        let profile = ServerProfile(
            id: editedProfile?.id ?? UUID(),
            label: fields.label.isEmpty ? fields.host : fields.label,
            host: fields.host,
            port: fields.port,
            rpcPath: fields.rpcPath,
            username: fields.username.isEmpty ? nil : fields.username,
            useHTTPS: fields.useHTTPS)
        do {
            if !fields.password.isEmpty {
                try keychain.setPassword(fields.password, for: profile.id)
            }
            if isCreating {
                try profileStore.add(profile)
            } else {
                try profileStore.update(profile)
            }
            onSaved()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview("Servers") {
    ServersPrefsPane()
        .environment(prefsPreviewProfileStore)
        .environment(prefsPreviewStore)
        .frame(width: 700, height: 480)
}
#endif
