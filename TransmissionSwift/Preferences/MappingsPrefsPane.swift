// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

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
    @State private var saveError: String?
    @State private var pendingRemoval: OpenMapping?

    private let keychain = KeychainStore()

    var body: some View {
        Form {
            Section {
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
        .alert(
            "Couldn't Update Mappings",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .sheet(item: $editingModel) { model in
            MappingEditorSheet(
                model: model,
                onDismiss: { editingModel = nil },
                sampleServer: activeSampleServer,
                sampleTorrent: torrentStore.inspector.detail ?? torrentStore.list.torrents.first,
                sampleDownloadDir: torrentStore.list.downloadDirectory,
                resolveSamplePassword: { effectiveSamplePassword() },
                onSave: { mapping in
                    do {
                        if mappingStore.mappings.contains(where: { $0.id == mapping.id }) {
                            try mappingStore.update(mapping)
                        } else {
                            try mappingStore.add(mapping)
                        }
                        return nil
                    } catch {
                        return error.localizedDescription
                    }
                },
                onDuplicate: model.existing.map { mapping in
                    {
                        // Open the copy so it can be renamed straight away.
                        if let copy = duplicate(mapping) { edit(copy) }
                    }
                },
                onRemove: model.existing.map { mapping in
                    {
                        editingModel = nil
                        remove(mapping)
                    }
                })
        }
        .confirmationDialog(
            "Remove Mapping?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { mapping in
            Button("Remove", role: .destructive) { remove(mapping) }
            Button("Cancel", role: .cancel) {}
        } message: { mapping in
            Text("“\(mapping.name)” will be deleted. This can't be undone.")
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
                edit(mapping)
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help("Mapping Details")
            .accessibilityLabel("Details for \(mapping.name)")
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { edit(mapping) }
        .contextMenu {
            Button("Edit…") { edit(mapping) }
            Button("Duplicate") { duplicate(mapping) }
            Divider()
            Button("Remove…", role: .destructive) { pendingRemoval = mapping }
        }
    }

    private func edit(_ mapping: OpenMapping) {
        editingModel = MappingEditorModel(existing: mapping)
    }

    @discardableResult
    private func duplicate(_ mapping: OpenMapping) -> OpenMapping? {
        var copy = mapping
        copy.id = UUID()
        copy.name = "\(mapping.name) (Copy)"
        do {
            try mappingStore.add(copy)
            return copy
        } catch {
            saveError = error.localizedDescription
            return nil
        }
    }

    private func remove(_ mapping: OpenMapping) {
        do {
            try mappingStore.remove(id: mapping.id)
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func scopeLabel(_ scope: MappingServerScope) -> String {
        switch scope {
        case .all:
            return "All Servers"
        case .local:
            return "All Local Servers"
        case .remote:
            return "All Remote Servers"
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

#if DEBUG
#Preview("Mappings") {
    MappingsPrefsPane()
        .environment(prefsPreviewProfileStore)
        .environment(prefsPreviewMappingStore)
        .environment(prefsPreviewStore)
        .frame(width: 700, height: 480)
}
#endif
