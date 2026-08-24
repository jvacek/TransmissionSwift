import SwiftUI
import TransmissionCore

struct SpeedPrefsPane: View {
    @Environment(TorrentStore.self) private var store

    var body: some View {
        if store.isConnected {
            Form {
                Section {
                    Toggle("Enable global download limit", isOn: boolBinding(\.downLimited))
                    if store.effectiveSessionSettings.downLimited {
                        limitRow(label: "Download limit", keyPath: \.downLimitKBps)
                    }
                    Toggle("Enable global upload limit", isOn: boolBinding(\.upLimited))
                    if store.effectiveSessionSettings.upLimited {
                        limitRow(label: "Upload limit", keyPath: \.upLimitKBps)
                    }
                } header: {
                    Text("Global Limits")
                } footer: {
                    Text("Applied to every torrent unless it overrides them.")
                }

                Section {
                    Toggle("Enable alternative (turtle) speed limits", isOn: boolBinding(\.altSpeedEnabled))
                    if store.effectiveSessionSettings.altSpeedEnabled {
                        limitRow(label: "Turtle download", keyPath: \.altSpeedDownKBps)
                        limitRow(label: "Turtle upload", keyPath: \.altSpeedUpKBps)
                    }
                    Toggle("Enable scheduled turtle times", isOn: boolBinding(\.altSpeedTimeEnabled))
                    if store.effectiveSessionSettings.altSpeedTimeEnabled {
                        TurtleTimeRow(
                            begin: intBinding(\.altSpeedTimeBeginMinutes), end: intBinding(\.altSpeedTimeEndMinutes))
                        TurtleScheduleDays(mask: intBinding(\.altSpeedTimeDayMask))
                    }
                } header: {
                    Text("Turtle Schedule")
                } footer: {
                    Text("Turtle speed limits override the global limits while active.")
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 460)
        } else {
            SessionNotConnectedView()
        }
    }

    private func limitRow(label: String, keyPath: WritableKeyPath<SessionSettings, Int>) -> some View {
        Stepper(value: intBinding(keyPath), in: 1...100_000, step: 10) {
            HStack {
                Text(label)
                TextField("", value: intBinding(keyPath), format: .number)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                Text("KB/s").foregroundStyle(.secondary)
            }
        }
    }

    private func boolBinding(_ keyPath: WritableKeyPath<SessionSettings, Bool>) -> Binding<Bool> {
        store.binding(keyPath: keyPath)
    }

    private func intBinding(_ keyPath: WritableKeyPath<SessionSettings, Int>) -> Binding<Int> {
        store.binding(keyPath: keyPath)
    }
}

#Preview("Speed — Connected") {
    SpeedPrefsPane()
        .environment(prefsPreviewStore)
        .frame(width: 480, height: 540)
}
