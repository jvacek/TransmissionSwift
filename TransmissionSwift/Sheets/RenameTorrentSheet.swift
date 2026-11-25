// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import TransmissionCore

#if DEBUG
import TransmissionTestSupport
#endif

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
            Text(L10n.text("Rename Torrent"))
                .font(.headline)
            if let current = currentName {
                Text(L10n.format("“%@”", current))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            TextField(L10n.text("Name"), text: $newName, prompt: Text(L10n.text("New Name")))
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

            SheetButtonRow(
                L10n.text("Rename"),
                busyTitle: L10n.text("Renaming…"),
                isBusy: isSaving,
                canConfirm: canApply,
                onCancel: { isPresented = false },
                onConfirm: { Task { await apply() } }
            )
        }
        .padding(20)
        .frame(width: 400)
        .interactiveDismissDisabled(isSaving)
        .onAppear {
            newName = currentName ?? ""
        }
    }

    private var currentName: String? {
        store.list.torrents.first(where: { $0.id == id })?.name
    }

    private var trimmedName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Only a slash is worth explaining: an empty or unchanged name simply
    /// keeps Rename disabled, the way Finder behaves.
    private var validationError: String? {
        trimmedName.contains("/") ? L10n.text("The name can't contain “/”.") : nil
    }

    private var canApply: Bool {
        !isSaving && store.actionsEnabled && validationError == nil
            && !trimmedName.isEmpty && trimmedName != currentName
    }

    private func apply() async {
        guard canApply else { return }
        isSaving = true
        defer { isSaving = false }
        saveError = nil
        let succeeded = await store.actions.renameTorrent(id, newName: trimmedName)
        if succeeded {
            isPresented = false
        } else {
            saveError = store.lastActionError?.localizedDescription ?? L10n.text("Failed to rename torrent.")
            store.lastActionError = nil
        }
    }
}

#if DEBUG
#Preview("Rename Torrent") {
    let store = TorrentStore(service: MockTorrentService())
    store.list.selectedTorrentIDs = [5]
    return RenameTorrentSheet(isPresented: .constant(true), id: 5)
        .environment(store)
        .frame(width: 400)
}
#endif
