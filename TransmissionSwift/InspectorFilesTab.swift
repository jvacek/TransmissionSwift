import SwiftUI
import TransmissionCore

/// Per-file selection and bandwidth priority. Mutations dispatch through the
/// store; the service broadcasts a fresh snapshot, which flows back in via
/// the parent's `torrent`.
struct InspectorFilesTab: View {
    @Environment(TorrentStore.self) private var store
    let torrent: Torrent

    var body: some View {
        Table(torrent.files) {
            TableColumn("") { file in
                Toggle("Download", isOn: wantedBinding(for: file))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityLabel("Download \(file.name)")
            }
            .width(20)

            TableColumn("Name") { file in
                HStack(spacing: 6) {
                    Image(systemName: "doc")
                        .foregroundStyle(.secondary)
                    Text(file.name)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .width(min: 120)

            TableColumn("Size") { file in
                Text(file.size.formattedSize)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(62)

            TableColumn("Progress") { file in
                ProgressBar(value: file.progress, status: file.progress >= 1 ? .seeding : .downloading)
            }
            .width(100)

            TableColumn("Priority") { file in
                Picker("Priority", selection: priorityBinding(for: file)) {
                    ForEach(FilePriorityChoice.allCases, id: \.self) { choice in
                        Text(choice.displayLabel).tag(choice)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel("Priority for \(file.name)")
            }
            .width(80)
        }
        .accessibilityIdentifier("inspector.files.table")
    }

    private func wantedBinding(for file: TorrentFile) -> Binding<Bool> {
        Binding(
            get: { file.wanted },
            set: { wanted in
                Task { await store.setFilesWanted(torrent.id, fileIDs: [file.id], wanted: wanted) }
            }
        )
    }

    private func priorityBinding(for file: TorrentFile) -> Binding<FilePriorityChoice> {
        Binding(
            get: { FilePriorityChoice(file: file) },
            set: { choice in
                Task {
                    if let priority = choice.priority {
                        if !file.wanted {
                            await store.setFilesWanted(
                                torrent.id, fileIDs: [file.id], wanted: true)
                        }
                        await store.setFilePriority(
                            torrent.id, fileIDs: [file.id], priority: priority)
                    } else {
                        await store.setFilesWanted(torrent.id, fileIDs: [file.id], wanted: false)
                    }
                }
            }
        )
    }
}

/// The Priority popup folds "don't download" into the priority choice, like
/// Transmission's own UI: High / Normal / Low / Skip.
private enum FilePriorityChoice: CaseIterable, Hashable {
    case high, normal, low, skip

    init(file: TorrentFile) {
        guard file.wanted else {
            self = .skip
            return
        }
        switch file.priority {
        case .high: self = .high
        case .normal: self = .normal
        case .low: self = .low
        }
    }

    var priority: TorrentPriority? {
        switch self {
        case .high: return .high
        case .normal: return .normal
        case .low: return .low
        case .skip: return nil
        }
    }

    var displayLabel: String {
        switch self {
        case .high: return "High"
        case .normal: return "Normal"
        case .low: return "Low"
        case .skip: return "Skip"
        }
    }
}

#Preview {
    InspectorFilesTab(torrent: Torrent.samples[4])
        .environment(TorrentStore(service: MockTorrentService()))
        .frame(width: 322, height: 400)
}
