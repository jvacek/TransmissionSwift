// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

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
                    LabeledContent(L10n.text("Default folder")) {
                        TextField("", text: stringBinding(\.downloadDirectory))
                            .monospaced()
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text(L10n.text("Downloads"))
                } footer: {
                    Text(
                        L10n.text(
                            "On the server's disk — where new torrents land unless given another destination."))
                }

                Section {
                    Toggle(
                        L10n.text("Honour seeding ratio by default"),
                        isOn: boolBinding(\.seedRatioLimited))
                    if store.session.effectiveSessionSettings.seedRatioLimited {
                        LabeledContent(L10n.text("Stop at ratio")) {
                            plainCell(
                                TextField(
                                    "", value: ratioBinding,
                                    format: .number.precision(.fractionLength(1))))
                        }
                    }
                    Toggle(
                        L10n.text("Honour idle seeding by default"),
                        isOn: boolBinding(\.idleSeedingLimitEnabled))
                    if store.session.effectiveSessionSettings.idleSeedingLimitEnabled {
                        LabeledContent(L10n.text("Stop after")) {
                            unitCell(
                                TextField("", value: intBinding(\.idleSeedingLimitMinutes), format: .number),
                                unit: L10n.text("min"))
                        }
                    }
                } header: {
                    Text(L10n.text("Global Seeding Defaults"))
                } footer: {
                    Text(L10n.text("The defaults applied to torrents set to “use global”."))
                }

                Section {
                    Toggle(
                        L10n.text("Limit simultaneous downloads"),
                        isOn: boolBinding(\.downloadQueueEnabled))
                    if store.session.effectiveSessionSettings.downloadQueueEnabled {
                        queueSizeRow(
                            label: L10n.text("Download queue"), keyPath: \.downloadQueueSize)
                    }
                    Toggle(L10n.text("Limit simultaneous seeds"), isOn: boolBinding(\.seedQueueEnabled))
                    if store.session.effectiveSessionSettings.seedQueueEnabled {
                        queueSizeRow(label: L10n.text("Seed queue"), keyPath: \.seedQueueSize)
                    }
                    Toggle(
                        L10n.text("Treat idle torrents as stalled"),
                        isOn: boolBinding(\.queueStalledEnabled))
                    if store.session.effectiveSessionSettings.queueStalledEnabled {
                        LabeledContent(L10n.text("Stalled after")) {
                            unitCell(
                                TextField("", value: intBinding(\.queueStalledMinutes), format: .number),
                                unit: L10n.text("min"))
                        }
                    }
                } header: {
                    Text(L10n.text("Queue"))
                } footer: {
                    Text(L10n.text("How many torrents transfer at once; stalled ones don't use a slot."))
                }
            }
            .formStyle(.grouped)
        } else {
            SessionNotConnectedView()
        }
    }

    private var ratioBinding: Binding<Double> {
        Binding(
            get: { store.session.effectiveSessionSettings.seedRatioLimit },
            set: { newValue in Task { await store.session.updateSessionSettings { $0.seedRatioLimit = newValue } } }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<SessionSettings, Bool>) -> Binding<Bool> {
        store.session.binding(keyPath: keyPath)
    }

    private func intBinding(_ keyPath: WritableKeyPath<SessionSettings, Int>) -> Binding<Int> {
        store.session.binding(keyPath: keyPath)
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
        store.session.binding(keyPath: keyPath)
    }
}

#if DEBUG
#Preview("Transfers — Connected") {
    TransfersPrefsPane()
        .environment(prefsPreviewStore)
        .frame(width: 480, height: 620)
}
#endif
