import SwiftUI
import TransmissionCore

struct SeedingPrefsPane: View {
    @Environment(TorrentStore.self) private var store

    var body: some View {
        if store.isConnected {
            Form {
                Section {
                    Toggle("Honour seeding ratio by default", isOn: boolBinding(\.seedRatioLimited))
                    if store.effectiveSessionSettings.seedRatioLimited {
                        Stepper(value: ratioBinding, in: 0.0...10.0, step: 0.1) {
                            HStack {
                                Text("Stop at ratio")
                                TextField("", value: ratioBinding, format: .number.precision(.fractionLength(1)))
                                    .frame(width: 60)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    Toggle("Honour idle seeding by default", isOn: boolBinding(\.idleSeedingLimitEnabled))
                    if store.effectiveSessionSettings.idleSeedingLimitEnabled {
                        Stepper(value: intBinding(\.idleSeedingLimitMinutes), in: 1...1440, step: 5) {
                            HStack {
                                Text("Stop after")
                                TextField("", value: intBinding(\.idleSeedingLimitMinutes), format: .number)
                                    .frame(width: 60)
                                    .multilineTextAlignment(.trailing)
                                Text("min").foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Global Seeding Defaults")
                } footer: {
                    Text("The defaults applied to torrents set to “use global”.")
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 460)
        } else {
            SessionNotConnectedView()
        }
    }

    private var ratioBinding: Binding<Double> {
        Binding(
            get: { store.effectiveSessionSettings.seedRatioLimit },
            set: { newValue in Task { await store.updateSessionSettings { $0.seedRatioLimit = newValue } } }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<SessionSettings, Bool>) -> Binding<Bool> {
        store.binding(keyPath: keyPath)
    }

    private func intBinding(_ keyPath: WritableKeyPath<SessionSettings, Int>) -> Binding<Int> {
        store.binding(keyPath: keyPath)
    }
}
