import SwiftUI
import TransmissionCore

/// Sheet for relocating one or more torrents on the daemon host.
///
/// The text field takes a path on the *daemon's* filesystem. Paths starting
/// with `/` are absolute (from the daemon's root); anything else is relative to
/// the daemon's default download directory (`store.downloadDirectory`). `..`
/// and `.` are resolved lexically so the preview always shows the real target.
/// `move` mirrors RPC `torrent-set-location`'s flag: true relocates the existing
/// data, false only repoints the torrent when the data was moved out-of-band.
struct SetLocationSheet: View {
    @Environment(TorrentStore.self) private var store
    @Binding var isPresented: Bool
    let ids: [Torrent.ID]

    @State private var location: String = ""
    @State private var moveData = true
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set Location")
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            ServerPathField(
                path: $location,
                defaultDirectory: store.downloadDirectory,
                folders: suggestions,
                torrentName: store.torrents.first { ids.contains($0.id) }?.name,
                isDisabled: isSaving)

            Toggle("Move data to the new location", isOn: $moveData)
                .disabled(isSaving)
                .help(
                    "On: Transmission moves the existing files. Off: only update the path (use when you moved the data yourself)."
                )

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(isSaving ? "Applying…" : "Apply") {
                    Task { await apply() }
                }
                .buttonStyle(.glassProminent)
                .disabled(isSaving || location.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { location = initialLocation }
    }

    private var initialLocation: String {
        let selected = store.torrents.filter { ids.contains($0.id) }
        if let first = selected.first {
            return first.downloadFolder
        }
        return store.downloadDirectory ?? ""
    }

    private var subtitle: String {
        ids.count == 1 ? "1 torrent selected" : "\(ids.count) torrents selected"
    }

    private var suggestions: [String] {
        knownFolderSuggestions(store.facets.folders.map(\.name))
    }

    private func apply() async {
        isSaving = true
        defer { isSaving = false }
        let trimmed = location.trimmingCharacters(in: .whitespaces)
        let resolved = resolveServerPath(trimmed, relativeTo: store.downloadDirectory)
        await store.setLocation(ids, location: resolved, move: moveData)
        isPresented = false
    }
}

#Preview("Set Location") {
    SetLocationSheet(isPresented: .constant(true), ids: [2])
        .environment(previewTorrentStore)
        .environment(TagColorStore())
        .frame(width: 460)
}
