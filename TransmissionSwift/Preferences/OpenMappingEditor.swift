import SwiftUI
import TransmissionCore

/// Editable list of file mappings for one server profile. Rendered inside the
/// `ServerProfileForm`'s "File Mappings" section; each row becomes an
/// "Open with…" item in the torrent context menu.
struct OpenMappingEditor: View {
    @Binding var mappings: [OpenMapping]
    /// Live form context (host/port/username) used for the preview and Test.
    var sampleServer: ServerProfile
    /// The torrent the preview/Test act on (inspector selection, else first in
    /// the list). Nil when there are no torrents.
    var sampleTorrent: Torrent?
    /// The password currently entered in the form, used for preview/Test.
    var samplePassword: String
    /// Resolves the effective password for Test (typed field, else Keychain).
    var resolveSamplePassword: () -> String
    /// The daemon's default download directory (when connected), for the
    /// `{download-dir}` placeholder in preview/Test.
    var sampleDownloadDir: String?

    /// Created fresh on every Add/Edit click. Presenting a non-nil model shows
    /// the sheet; the sheet content receives the model directly (via
    /// `sheet(item:)`), so the fields are always seeded from the mapping being
    /// edited.
    @State private var editingModel: MappingEditorModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                "A mapping describes how this server's download folders are reachable from this Mac, so a torrent's context menu can open them in an external app. Mappings are stored with the server — changes apply when you click Save Changes below."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach($mappings) { $mapping in
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
                        if mapping.action == .finder {
                            Text("Reveals in Finder")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        } else if let bundleID = mapping.applicationBundleID {
                            Text("Opens in \(MappingLauncher.displayName(for: bundleID) ?? bundleID)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if mapping.accessBookmark != nil {
                            Text("Access granted")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
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
                        mappings.removeAll { $0.id == mapping.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete mapping")
                }
            }

            Button {
                editingModel = MappingEditorModel(existing: nil)
            } label: {
                Label("Add Mapping…", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
        .sheet(item: $editingModel) { model in
            MappingEditorSheet(
                model: model,
                onCancel: { editingModel = nil },
                sampleServer: sampleServer,
                sampleTorrent: sampleTorrent,
                samplePassword: samplePassword,
                sampleDownloadDir: sampleDownloadDir,
                resolveSamplePassword: resolveSamplePassword,
                onSave: { mapping in
                    if let index = mappings.firstIndex(where: { $0.id == mapping.id }) {
                        mappings[index] = mapping
                    } else {
                        mappings.append(mapping)
                    }
                    editingModel = nil
                }
            )
        }
    }
}
