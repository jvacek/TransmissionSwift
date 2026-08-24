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
                    LabeledContent("Peer listening port") {
                        TextField("Port", value: intBinding(\.peerPort), format: .number.grouping(.never))
                            .frame(width: 80)
                    }
                    Toggle("Pick random port on launch", isOn: boolBinding(\.peerPortRandomOnStart))
                    Toggle("Enable UPnP/NAT-PMP port forwarding", isOn: boolBinding(\.portForwardingEnabled))
                } header: {
                    Text("Connections")
                }

                Section {
                    LabeledContent("Encryption") {
                        Picker("", selection: encryptionBinding) {
                            Text("Prefer encrypted").tag(EncryptionChoice.preferred)
                            Text("Require encrypted").tag(EncryptionChoice.required)
                            Text("Allow unencrypted").tag(EncryptionChoice.tolerated)
                        }
                        .labelsHidden()
                        .frame(maxWidth: 200)
                    }
                    Toggle("Enable blocklist", isOn: boolBinding(\.blocklistEnabled))
                    if store.effectiveSessionSettings.blocklistEnabled {
                        TextField("Blocklist URL", text: stringBinding(\.blocklistURL))
                            .font(.monospaced(.body)())
                    }
                } header: {
                    Text("Privacy")
                }

                Section {
                    Toggle("Enable Peer Exchange (PEX)", isOn: boolBinding(\.pexEnabled))
                    Toggle("Enable DHT", isOn: boolBinding(\.dhtEnabled))
                    Toggle("Enable µTP", isOn: boolBinding(\.utpEnabled))
                    Toggle("Enable Local Peer Discovery (LPD)", isOn: boolBinding(\.lpdEnabled))
                } header: {
                    Text("Protocol")
                }

                Section {
                    Toggle("Limit simultaneous downloads", isOn: boolBinding(\.downloadQueueEnabled))
                    if store.effectiveSessionSettings.downloadQueueEnabled {
                        queueSizeRow(label: "Download queue", keyPath: \.downloadQueueSize)
                    }
                    Toggle("Limit simultaneous seeds", isOn: boolBinding(\.seedQueueEnabled))
                    if store.effectiveSessionSettings.seedQueueEnabled {
                        queueSizeRow(label: "Seed queue", keyPath: \.seedQueueSize)
                    }
                    Toggle("Treat idle torrents as stalled", isOn: boolBinding(\.queueStalledEnabled))
                    if store.effectiveSessionSettings.queueStalledEnabled {
                        Stepper(value: intBinding(\.queueStalledMinutes), in: 1...1440, step: 5) {
                            HStack {
                                Text("Stalled after")
                                TextField("", value: intBinding(\.queueStalledMinutes), format: .number)
                                    .frame(width: 60)
                                    .multilineTextAlignment(.trailing)
                                Text("min").foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Queue")
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 460)
        } else {
            SessionNotConnectedView()
        }
    }

    private func queueSizeRow(label: String, keyPath: WritableKeyPath<SessionSettings, Int>) -> some View {
        Stepper(value: intBinding(keyPath), in: 1...100, step: 1) {
            HStack {
                Text(label)
                TextField("", value: intBinding(keyPath), format: .number)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var encryptionBinding: Binding<EncryptionChoice> {
        Binding(
            get: { EncryptionChoice(rawValue: store.effectiveSessionSettings.encryption.rawValue) ?? .preferred },
            set: { choice in
                let value: SessionEncryption
                switch choice {
                case .required: value = .required
                case .preferred: value = .preferred
                case .tolerated: value = .tolerated
                }
                Task { await store.updateSessionSettings { $0.encryption = value } }
            }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<SessionSettings, Bool>) -> Binding<Bool> {
        store.binding(keyPath: keyPath)
    }

    private func intBinding(_ keyPath: WritableKeyPath<SessionSettings, Int>) -> Binding<Int> {
        store.binding(keyPath: keyPath)
    }

    private func stringBinding(_ keyPath: WritableKeyPath<SessionSettings, String>) -> Binding<String> {
        store.binding(keyPath: keyPath)
    }
}
