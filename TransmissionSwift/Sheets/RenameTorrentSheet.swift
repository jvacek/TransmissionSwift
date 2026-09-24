import SwiftUI
import TransmissionCore

/// Sheet for renaming a torrent's root (its display name).
///
/// Maps to RPC `torrent-rename-path` with `path` = the torrent's current name.
/// The new name must be a single path component — empty input and names
/// containing `/` are rejected client-side; anything else (e.g. a name the
/// daemon rejects) surfaces via `lastActionError` after Apply.
struct RenameTorrentSheet: View {
    @Environment(TorrentStore.self) private var store
    @Binding var isPresented: Bool
    let id: Torrent.ID

    @State private var newName: String = ""
    @State private var isSaving = false
    @State private var saveError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename Torrent")
                .font(.headline)
            if let current = currentName {
                Text("“\(current)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            TextField("New name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .disabled(isSaving)
                .onSubmit { Task { await apply() } }

            if let validationError {
                Text(validationError)
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
                Button(isSaving ? "Renaming…" : "Rename") {
                    Task { await apply() }
                }
                .buttonStyle(.glassProminent)
                .disabled(!canApply)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            newName = currentName ?? ""
        }
    }

    private var currentName: String? {
        store.torrents.first(where: { $0.id == id })?.name
    }

    private var trimmedName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validationError: String? {
        if trimmedName.isEmpty { return "Enter a new name." }
        if trimmedName.contains("/") { return "The name can't contain “/”." }
        if trimmedName == currentName { return "Enter a different name." }
        return nil
    }

    private var canApply: Bool {
        !isSaving && validationError == nil && store.actionsEnabled
    }

    private func apply() async {
        guard canApply else { return }
        isSaving = true
        defer { isSaving = false }
        saveError = nil
        let succeeded = await store.renameTorrent(id, newName: trimmedName)
        if succeeded {
            isPresented = false
        } else {
            saveError = store.lastActionError?.localizedDescription ?? "Failed to rename torrent."
        }
    }
}

#Preview("Rename Torrent") {
    let store = TorrentStore(service: MockTorrentService())
    store.selectedTorrentIDs = [5]
    return RenameTorrentSheet(isPresented: .constant(true), id: 5)
        .environment(store)
        .frame(width: 400)
}
