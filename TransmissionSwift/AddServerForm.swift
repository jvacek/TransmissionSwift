//
//  AddServerForm.swift
//  TransmissionSwift
//
//  Created by Jonas Vacek on 10/06/2026.
//

import SwiftUI
import TransmissionCore

struct AddServerForm: View {
    @Environment(ServerProfileStore.self) private var profileStore

    @State private var label = ""
    @State private var host = "localhost"
    @State private var port = 9091
    @State private var username = ""
    @State private var password = ""
    @State private var useHTTPS = false
    @State private var saveError: String?

    private let keychain = KeychainStore()

    var body: some View {
        Form {
            Section("Add a Transmission server") {
                TextField("Label", text: $label, prompt: Text("Home NAS"))
                    .accessibilityIdentifier("addServer.label")
                TextField("Host", text: $host)
                    .accessibilityIdentifier("addServer.host")
                TextField("Port", value: $port, format: .number.grouping(.never))
                    .accessibilityIdentifier("addServer.port")
                TextField("Username", text: $username, prompt: Text("optional"))
                    .accessibilityIdentifier("addServer.username")
                SecureField("Password", text: $password)
                    .accessibilityIdentifier("addServer.password")
                Toggle("Use HTTPS", isOn: $useHTTPS)
                    .accessibilityIdentifier("addServer.https")
            }
            if let saveError {
                Text(saveError)
                    .foregroundStyle(.red)
            }
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(host.isEmpty)
                .accessibilityIdentifier("addServer.save")
        }
        .formStyle(.grouped)
        .padding()
    }

    private func save() {
        let profile = ServerProfile(
            label: label.isEmpty ? host : label,
            host: host,
            port: port,
            username: username.isEmpty ? nil : username,
            useHTTPS: useHTTPS
        )
        do {
            if !username.isEmpty {
                try keychain.setPassword(password, for: profile.id)
            }
            try profileStore.add(profile)
        } catch {
            saveError = error.localizedDescription
        }
    }
}
