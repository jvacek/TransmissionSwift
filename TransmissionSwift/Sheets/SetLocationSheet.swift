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
    var serverName: String? = nil

    @State private var location: String = ""
    @State private var moveData = true
    @State private var isSaving = false
    @State private var isMixed = false
    @State private var distinctCount = 0
    @State private var currentFolders: [String] = []
    @State private var saveError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set Location")
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            if isMixed {
                Text("They are in different folders — applying sets all to the same location.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ServerPathField(
                path: $location,
                defaultDirectory: store.downloadDirectory,
                folders: suggestions,
                serverName: serverName
            )

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Move data to the new location", isOn: $moveData)
                    .disabled(isSaving)
                Text(moveCaption)
                    .font(.caption)
                    .foregroundStyle(moveData ? Color.secondary : Color.orange)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isNoOp {
                Text("Already at this location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(isSaving ? "Applying…" : "Apply") {
                    Task { await apply() }
                }
                .buttonStyle(.glassProminent)
                .disabled(!canApply)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            let folders = store.torrents.filter { ids.contains($0.id) }.map(\.downloadFolder)
            currentFolders = folders
            let initial = setLocationInitialState(
                folders: folders, relativeTo: store.downloadDirectory)
            location = initial.path
            distinctCount = initial.distinctCount
            isMixed = initial.distinctCount > 1
        }
    }

    private var subtitle: String {
        if isMixed {
            let torrents = ids.count == 1 ? "1 torrent" : "\(ids.count) torrents"
            return "\(torrents) selected · in \(distinctCount) different folders"
        }
        return ids.count == 1 ? "1 torrent selected" : "\(ids.count) torrents selected"
    }

    private var moveCaption: String {
        if moveData {
            return "Transmission moves the existing files for you."
        }
        return
            "Only use this if you already moved the files yourself (e.g. via SSH) — otherwise the torrents will error."
    }

    private var resolvedLocation: String {
        resolveServerPath(
            location.trimmingCharacters(in: .whitespaces), relativeTo: store.downloadDirectory)
    }

    /// Applying to the folders every selected torrent already shares is a no-op.
    private var isNoOp: Bool {
        guard !currentFolders.isEmpty else { return false }
        let target = resolvedLocation.normalizedDownloadPath
        return currentFolders.allSatisfy { $0.normalizedDownloadPath == target }
    }

    /// Empty input resolves to the default dir, so it's a valid target as long
    /// as we know the base. See `isSubmittableServerPath`.
    private var canApply: Bool {
        !isSaving && !isNoOp
            && isSubmittableServerPath(location, relativeTo: store.downloadDirectory)
    }

    private var suggestions: [String] {
        serverPathSuggestions(from: store.facets)
    }

    private func apply() async {
        isSaving = true
        defer { isSaving = false }
        saveError = nil
        let succeeded = await store.setLocation(ids, location: resolvedLocation, move: moveData)
        if succeeded {
            isPresented = false
        } else {
            saveError = store.lastActionError?.localizedDescription ?? "Failed to set location."
        }
    }
}

#Preview("Set Location") {
    SetLocationSheet(isPresented: .constant(true), ids: [2], serverName: "Home NAS")
        .environment(previewTorrentStore)
        .environment(TagColorStore())
        .frame(width: 460)
}
