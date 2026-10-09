import SwiftUI
import TransmissionCore

/// App-wide "Open with…" mappings, moved out of each server profile. Each
/// mapping lists which servers it applies to; the scope is edited in
/// `MappingEditorSheet`, and summarised on the row here.
struct MappingsPrefsPane: View {
    @Environment(OpenMappingStore.self) private var mappingStore
    @Environment(ServerProfileStore.self) private var profileStore
    @Environment(TorrentStore.self) private var torrentStore

    /// Created fresh on every Add/Edit click; a non-nil model shows the sheet.
    @State private var editingModel: MappingEditorModel?

    private let keychain = KeychainStore()

    var body: some View {
        Form {
            Section {
                Text(
                    "A mapping describes how a server's download folders are reachable from this Mac, so a torrent's context menu can open them in an external app. Mappings are app-wide; each one lists the servers it applies to."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if mappingStore.mappings.isEmpty {
                    Text("No mappings yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(mappingStore.mappings) { mapping in
                        row(mapping)
                    }
                }

                Button {
                    editingModel = MappingEditorModel(existing: nil)
                } label: {
                    Label("Add Mapping…", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            } header: {
                Text("File Mappings")
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editingModel) { model in
            MappingEditorSheet(
                model: model,
                onCancel: { editingModel = nil },
                sampleServer: activeSampleServer,
                sampleTorrent: torrentStore.inspector.detail ?? torrentStore.list.torrents.first,
                samplePassword: "",
                sampleDownloadDir: torrentStore.list.downloadDirectory,
                resolveSamplePassword: { effectiveSamplePassword() },
                onSave: { mapping in
                    if mappingStore.mappings.contains(where: { $0.id == mapping.id }) {
                        try? mappingStore.update(mapping)
                    } else {
                        try? mappingStore.add(mapping)
                    }
                    editingModel = nil
                })
        }
    }

    private func row(_ mapping: OpenMapping) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mapping.name)
                    .fontWeight(.medium)
                Text(mapping.template)
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(scopeLabel(mapping.scope))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                editingModel = MappingEditorModel(existing: mapping)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit mapping")
            Button {
                try? mappingStore.remove(id: mapping.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Delete mapping")
        }
    }

    private func scopeLabel(_ scope: MappingServerScope) -> String {
        switch scope {
        case .all:
            return "All Servers"
        case .only(let ids):
            let labels = profileStore.profiles.filter { ids.contains($0.id) }.map(\.label)
            switch labels.count {
            case 0: return "No servers"
            case 1: return labels[0]
            default: return "\(labels[0]) +\(labels.count - 1)"
            }
        }
    }

    /// The context the preview and Test expand against: the active server.
    private var activeSampleServer: ServerProfile {
        profileStore.activeProfile ?? ServerProfile(label: "", host: "localhost")
    }

    /// Password the Test uses, from the active server's Keychain secret.
    private func effectiveSamplePassword() -> String {
        guard let id = profileStore.activeProfile?.id else { return "" }
        return (try? keychain.password(for: id)) ?? ""
    }
}

#Preview("Mappings") {
    MappingsPrefsPane()
        .environment(prefsPreviewProfileStore)
        .environment(prefsPreviewMappingStore)
        .environment(prefsPreviewStore)
        .frame(width: 700, height: 480)
}
