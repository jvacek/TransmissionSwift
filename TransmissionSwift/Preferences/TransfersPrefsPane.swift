import SwiftUI
import TransmissionCore

struct TransfersPrefsPane: View {
    @Environment(TorrentStore.self) private var store

    private static let fieldWidth: CGFloat = 60
    private static let unitSlotWidth: CGFloat = 34

    var body: some View {
        if store.isConnected {
            Form {
                Section {
                    LabeledContent("Default folder") {
                        TextField("", text: stringBinding(\.downloadDirectory))
                            .monospaced()
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Downloads")
                } footer: {
                    Text("On the server's disk — where new torrents land unless given another destination.")
                }

                Section {
                    Toggle("Honour seeding ratio by default", isOn: boolBinding(\.seedRatioLimited))
                    if store.effectiveSessionSettings.seedRatioLimited {
                        LabeledContent("Stop at ratio") {
                            plainCell(
                                TextField(
                                    "", value: ratioBinding,
                                    format: .number.precision(.fractionLength(1))))
                        }
                    }
                    Toggle("Honour idle seeding by default", isOn: boolBinding(\.idleSeedingLimitEnabled))
                    if store.effectiveSessionSettings.idleSeedingLimitEnabled {
                        LabeledContent("Stop after") {
                            unitCell(
                                TextField("", value: intBinding(\.idleSeedingLimitMinutes), format: .number),
                                unit: "min")
                        }
                    }
                } header: {
                    Text("Global Seeding Defaults")
                } footer: {
                    Text("The defaults applied to torrents set to “use global”.")
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
                        LabeledContent("Stalled after") {
                            unitCell(
                                TextField("", value: intBinding(\.queueStalledMinutes), format: .number),
                                unit: "min")
                        }
                    }
                } header: {
                    Text("Queue")
                } footer: {
                    Text("How many torrents transfer at once; stalled ones don't use a slot.")
                }
            }
            .formStyle(.grouped)
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

    private func queueSizeRow(label: String, keyPath: WritableKeyPath<SessionSettings, Int>) -> some View {
        LabeledContent(label) {
            plainCell(TextField("", value: intBinding(keyPath), format: .number))
        }
    }

    /// Numeric cells share one geometry — a 60pt field plus a fixed unit slot —
    /// so fields line up and every row renders at the same height, whether or
    /// not the row carries a unit suffix.
    private func plainCell(_ field: some View) -> some View {
        HStack(spacing: 4) {
            field
                .frame(width: Self.fieldWidth)
                .multilineTextAlignment(.trailing)
            Color.clear.frame(width: Self.unitSlotWidth)
        }
    }

    private func unitCell(_ field: some View, unit: String) -> some View {
        HStack(spacing: 4) {
            field
                .frame(width: Self.fieldWidth)
                .multilineTextAlignment(.trailing)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: Self.unitSlotWidth, alignment: .leading)
        }
    }

    private func stringBinding(_ keyPath: WritableKeyPath<SessionSettings, String>) -> Binding<String> {
        store.binding(keyPath: keyPath)
    }
}

#Preview("Transfers — Connected") {
    TransfersPrefsPane()
        .environment(prefsPreviewStore)
        .frame(width: 480, height: 620)
}
