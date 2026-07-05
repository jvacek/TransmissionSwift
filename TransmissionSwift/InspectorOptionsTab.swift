import SwiftUI
import TransmissionCore

/// Per-torrent transfer options as a System-Settings-style grouped form.
/// Edits a local draft and pushes the whole struct through
/// `store.setOptions` on every change; detail rows appear only while their
/// enabling toggle is on (progressive disclosure, like System Settings).
struct InspectorOptionsTab: View {
    @Environment(TorrentStore.self) private var store
    let torrent: Torrent
    @State private var options: TorrentOptions

    init(torrent: Torrent) {
        self.torrent = torrent
        _options = State(initialValue: torrent.options)
    }

    var body: some View {
        Form {
            Section("Bandwidth") {
                Toggle("Honor global speed limits", isOn: $options.honorsSessionLimits)

                Toggle("Limit download", isOn: $options.downloadLimited)
                if options.downloadLimited {
                    numberRow(
                        "Download limit", value: $options.downloadLimitKBps,
                        range: 1...1_000_000, step: 50, unit: "KB/s")
                }

                Toggle("Limit upload", isOn: $options.uploadLimited)
                if options.uploadLimited {
                    numberRow(
                        "Upload limit", value: $options.uploadLimitKBps,
                        range: 1...1_000_000, step: 50, unit: "KB/s")
                }
            }

            Section("Seeding") {
                Toggle("Stop seeding at ratio", isOn: $options.seedRatioLimited)
                if options.seedRatioLimited {
                    LabeledContent("Ratio") {
                        TextField(
                            "Ratio", value: $options.seedRatioLimit,
                            format: .number.precision(.fractionLength(2))
                        )
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                    }
                }

                Toggle("Stop seeding when idle", isOn: $options.seedIdleLimited)
                if options.seedIdleLimited {
                    numberRow(
                        "Idle time", value: $options.seedIdleMinutes,
                        range: 1...10_080, step: 5, unit: "min")
                }
            }

            Section("Peers") {
                numberRow("Maximum peers", value: $options.peerLimit, range: 1...500, step: 5)
            }
        }
        .formStyle(.grouped)
        // Option writes exist, but current option values are not fetched from RPC yet.
        .disabled(true)
        .onChange(of: options) { _, newValue in
            Task { await store.setOptions(torrent.id, options: newValue) }
        }
    }

    private func numberRow(
        _ label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int,
        unit: String? = nil
    ) -> some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                TextField(label, value: value, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                Stepper(label, value: value, in: range, step: step)
                    .labelsHidden()
                if let unit {
                    Text(unit)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    InspectorOptionsTab(torrent: Torrent.samples[4])
        .environment(TorrentStore(service: MockTorrentService()))
        .frame(width: 322, height: 600)
}
