// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import TransmissionCore

struct NetworkPrefsPane: View {
    @Environment(TorrentStore.self) private var store

    private enum EncryptionChoice: String, CaseIterable {
        case preferred, required, tolerated
    }

    var body: some View {
        if store.isConnected {
            Form {
                Section {
                    LabeledContent(L10n.text("Peer listening port")) {
                        TextField(
                            L10n.text("Port"), value: intBinding(\.peerPort),
                            format: .number.grouping(.never)
                        )
                        .frame(width: 80)
                    }
                    Toggle(
                        L10n.text("Pick random port on launch"),
                        isOn: boolBinding(\.peerPortRandomOnStart))
                    Toggle(
                        L10n.text("Enable UPnP/NAT-PMP port forwarding"),
                        isOn: boolBinding(\.portForwardingEnabled))
                    LabeledContent(L10n.text("Port status")) {
                        portStatusRow
                    }
                } header: {
                    Text(L10n.text("Connections"))
                } footer: {
                    Text(L10n.text("Tests whether the listening port is reachable from the outside."))
                }

                Section {
                    LabeledContent(L10n.text("Encryption")) {
                        Picker("", selection: encryptionBinding) {
                            Text(L10n.text("Prefer encrypted")).tag(EncryptionChoice.preferred)
                            Text(L10n.text("Require encrypted")).tag(EncryptionChoice.required)
                            Text(L10n.text("Allow unencrypted")).tag(EncryptionChoice.tolerated)
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    Toggle(L10n.text("Enable blocklist"), isOn: boolBinding(\.blocklistEnabled))
                    if store.session.effectiveSessionSettings.blocklistEnabled {
                        TextField(L10n.text("Blocklist URL"), text: stringBinding(\.blocklistURL))
                            .font(.monospaced(.body)())
                    }
                } header: {
                    Text(L10n.text("Privacy"))
                }

                Section {
                    Toggle(L10n.text("Enable Peer Exchange (PEX)"), isOn: boolBinding(\.pexEnabled))
                    Toggle(L10n.text("Enable DHT"), isOn: boolBinding(\.dhtEnabled))
                    Toggle(L10n.text("Enable µTP"), isOn: boolBinding(\.utpEnabled))
                    Toggle(
                        L10n.text("Enable Local Peer Discovery (LPD)"),
                        isOn: boolBinding(\.lpdEnabled))
                } header: {
                    Text(L10n.text("Protocol"))
                }
            }
            .formStyle(.grouped)
        } else {
            SessionNotConnectedView()
        }
    }

    private var portStatusRow: some View {
        HStack {
            switch store.session.portIsOpen {
            case .some(true):
                Label(L10n.text("Open"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .some(false):
                Label(L10n.text("Closed"), systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .none:
                Text(L10n.text("Not tested"))
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await store.session.testPort() }
            } label: {
                Label(L10n.text("Test"), systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
            }
            .controlSize(.small)
        }
    }

    private var encryptionBinding: Binding<EncryptionChoice> {
        Binding(
            get: {
                EncryptionChoice(rawValue: store.session.effectiveSessionSettings.encryption.rawValue) ?? .preferred
            },
            set: { choice in
                let value: SessionEncryption
                switch choice {
                case .required: value = .required
                case .preferred: value = .preferred
                case .tolerated: value = .tolerated
                }
                Task { await store.session.updateSessionSettings { $0.encryption = value } }
            }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<SessionSettings, Bool>) -> Binding<Bool> {
        store.session.binding(keyPath: keyPath)
    }

    private func intBinding(_ keyPath: WritableKeyPath<SessionSettings, Int>) -> Binding<Int> {
        store.session.binding(keyPath: keyPath)
    }

    private func stringBinding(_ keyPath: WritableKeyPath<SessionSettings, String>) -> Binding<String> {
        store.session.binding(keyPath: keyPath)
    }
}

#if DEBUG
#Preview("Network — Connected") {
    NetworkPrefsPane()
        .environment(prefsPreviewStore)
        .frame(width: 480, height: 1000)
}
#endif

#if DEBUG
#Preview("Session — Not Connected") {
    NetworkPrefsPane()
        .environment(prefsDisconnectedPreviewStore)
        .frame(width: 480, height: 360)
}
#endif
