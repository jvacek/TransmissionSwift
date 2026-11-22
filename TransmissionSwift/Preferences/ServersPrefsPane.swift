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
                onSaved: { editor = nil },
                onDuplicate: editorAction(for: target) { profile in
                    // Open the copy so it can be renamed straight away.
                    if let copy = duplicate(profile.id) { editor = .edit(copy) }
                },
                onRemove: editorAction(for: target) { profile in
                    editor = nil
                    removeServer(profile.id)
                })
        }
    }

    /// Duplicate and Remove only exist for a saved server.
    private func editorAction(
        for target: ServerEditorTarget, _ action: @escaping (ServerProfile) -> Void
    ) -> (() -> Void)? {
        guard case .edit(let profile) = target else { return nil }
        return { action(profile) }
    }

    private func serverRow(_ profile: ServerProfile) -> some View {
        let isActive = profileStore.activeProfile?.id == profile.id
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.label)
                    .fontWeight(isActive ? .semibold : .regular)
                Text(verbatim: "\(profile.host):\(profile.port)")
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
            Button {
                editor = .edit(profile)
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help("Server Details")
            .accessibilityLabel("Details for \(profile.label)")
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
    @discardableResult
    private func duplicate(_ id: UUID) -> ServerProfile? {
        do {
            guard let copy = try profileStore.duplicate(id: id) else { return nil }
            do {
                if let password = try keychain.password(for: id), !password.isEmpty {
                    try keychain.setPassword(password, for: copy.id)
                }
            } catch {
                actionError = "The copy was created, but its saved password couldn't be copied."
            }
            return copy
        } catch {
            actionError = error.localizedDescription
            return nil
        }
    }

    private func removeServer(_ id: UUID) {
        do {
            try profileStore.remove(id: id)
            // The profile id is never reused, so an orphaned secret would sit
            // in the Keychain forever.
            try? keychain.deletePassword(for: id)
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
    let onDuplicate: (() -> Void)?
    let onRemove: (() -> Void)?

    @Environment(ServerProfileStore.self) private var profileStore

    @State private var fields: Fields
    @State private var hasStoredPassword = false
    @State private var removesStoredPassword = false
    /// Fixed for the sheet's lifetime, so a save retried after a Keychain
    /// failure writes to the profile the first attempt already added.
    @State private var draftID = UUID()
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testFailed = false
    @State private var saveError: String?
    @State private var confirmingRemoval = false

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

    init(
        target: ServerEditorTarget,
        onCancel: @escaping () -> Void,
        onSaved: @escaping () -> Void,
        onDuplicate: (() -> Void)? = nil,
        onRemove: (() -> Void)? = nil
    ) {
        self.target = target
        self.onCancel = onCancel
        self.onSaved = onSaved
        self.onDuplicate = onDuplicate
        self.onRemove = onRemove
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
                    TextField(
                        "Port",
                        value: $fields.port,
                        format: .number.grouping(.never),
                        prompt: Text("9091")
                    )
                    TextField("RPC path", text: $fields.rpcPath, prompt: Text("/transmission/rpc"))
                    Toggle("Use HTTPS", isOn: $fields.useHTTPS)
                    HStack(spacing: 8) {
                        Button("Test Connection") {
                            Task { await runConnectionTest() }
                        }
                        .disabled(isTesting || !isValid)
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        if let testMessage {
                            Text(testMessage)
                                .font(.caption)
                                .foregroundStyle(testFailed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                                .lineLimit(2)
                                .help(testMessage)
                        }
                    }
                }

                Section("Authentication") {
                    TextField("Username", text: $fields.username, prompt: Text("Optional"))
                    SecureField(
                        "Password",
                        text: $fields.password,
                        prompt: Text(keepsStoredPassword ? "Leave blank to keep" : "Optional")
                    )
                    if hasStoredPassword {
                        HStack {
                            if removesStoredPassword {
                                Text("The saved password will be removed when you save.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Keep Saved Password") { removesStoredPassword = false }
                            } else {
                                Spacer()
                                Button("Remove Saved Password") { removesStoredPassword = true }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }

            SheetButtonRow(
                isCreating ? "Add Server" : "Save",
                canConfirm: canSave,
                onCancel: onCancel,
                onConfirm: save
            ) {
                if let onDuplicate {
                    Button("Duplicate", action: onDuplicate)
                        .disabled(isDirty)
                        .help(isDirty ? "Save or cancel your changes first" : "Make a copy of this server")
                }
                if onRemove != nil {
                    Button("Remove…", role: .destructive) { confirmingRemoval = true }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 20)
        .frame(width: 480, height: 520)
        .confirmationDialog("Remove Server?", isPresented: $confirmingRemoval) {
            Button("Remove", role: .destructive) { onRemove?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The saved password will be deleted. Torrents on the daemon are not affected.")
        }
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

    private var isDirty: Bool { fields != initialFields || removesStoredPassword }

    private var keepsStoredPassword: Bool { hasStoredPassword && !removesStoredPassword }

    /// The profile the fields describe, trimmed. Save, validation and Test all
    /// read this one value so they can't disagree about what gets stored.
    private var candidate: ServerProfile {
        let host = fields.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = fields.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = fields.username.trimmingCharacters(in: .whitespacesAndNewlines)
        return ServerProfile(
            id: editedProfile?.id ?? draftID,
            label: label.isEmpty ? host : label,
            host: host,
            port: fields.port,
            rpcPath: fields.rpcPath.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username.isEmpty ? nil : username,
            useHTTPS: fields.useHTTPS)
    }

    private var isValid: Bool {
        let profile = candidate
        return !profile.host.isEmpty && (1...65535).contains(profile.port) && profile.rpcURL != nil
    }

    private var canSave: Bool { isValid && isDirty }

    private func runConnectionTest() async {
        isTesting = true
        testMessage = nil
        defer { isTesting = false }

        let probe = candidate
        guard let rpcURL = probe.rpcURL else {
            testFailed = true
            testMessage = "Invalid URL"
            return
        }

        var credentials: Credentials?
        if let username = probe.username {
            let pwd: String
            if !fields.password.isEmpty {
                pwd = fields.password
            } else if keepsStoredPassword, let profile = editedProfile {
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
                credentials = Credentials(username: username, password: pwd)
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
        guard canSave else { return }
        let profile = candidate
        saveError = nil
        do {
            // Profile first: if the Keychain write then fails, a retry updates
            // this same profile instead of leaving a secret with no owner.
            if profileStore.profiles.contains(where: { $0.id == profile.id }) {
                try profileStore.update(profile)
            } else {
                try profileStore.add(profile)
            }
        } catch {
            saveError = error.localizedDescription
            return
        }
        do {
            if profile.username == nil || (removesStoredPassword && fields.password.isEmpty) {
                try keychain.deletePassword(for: profile.id)
            } else if !fields.password.isEmpty {
                try keychain.setPassword(fields.password, for: profile.id)
            }
        } catch {
            saveError = "The server was saved, but the password couldn't be updated in the Keychain."
            return
        }
        onSaved()
    }
}

#if DEBUG
#Preview("Servers") {
    ServersPrefsPane()
        .environment(prefsPreviewProfileStore)
        .environment(prefsPreviewStore)
        .frame(width: 700, height: 480)
}

#Preview("Edit Server") {
    ServerProfileForm(
        target: .edit(ServerProfile(label: "Home NAS", host: "nas.local")),
        onCancel: {}, onSaved: {}, onDuplicate: {}, onRemove: {}
    )
    .environment(prefsPreviewProfileStore)
}
#endif
