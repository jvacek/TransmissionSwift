// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import TransmissionCore

#if DEBUG
import TransmissionTestSupport
#endif

/// Dedicated popup for editing a torrent's labels. Prefills with the union of
/// the target set's labels and applies only the difference: labels the user
/// added go onto every target, labels they removed come off every target, and
/// each torrent keeps the rest of its own labels. `torrent-set labels` replaces
/// the whole set, so targets are grouped by their resulting set.
struct EditLabelsSheet: View {
    @Environment(TorrentStore.self) private var store
    @Binding var isPresented: Bool
    let ids: [Torrent.ID]

    @State private var tags: [String] = []
    @State private var initial: Set<String> = []
    @State private var isSaving = false
    @State private var saveError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Labels")
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            TagsInputField(tags: $tags, suggestions: suggestions)
                .disabled(!store.actionsEnabled || isSaving)

            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SheetButtonRow(
                "Apply",
                busyTitle: "Applying…",
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
            let merged = Self.mergedLabels(store.list.torrents, ids: ids)
            initial = Set(merged)
            tags = merged
        }
    }

    private var canApply: Bool {
        !isSaving && store.actionsEnabled && Set(tags) != initial
    }

    /// Union of the selection's labels, shown as the starting point.
    nonisolated static func mergedLabels(_ torrents: [Torrent], ids: [Torrent.ID]) -> [String] {
        let wanted = Set(ids)
        return Set(torrents.lazy.filter { wanted.contains($0.id) }.flatMap(\.labels)).sorted()
    }

    nonisolated struct LabelUpdate: Equatable, Sendable {
        let labels: [String]
        let ids: [Torrent.ID]
    }

    /// The writes that turn `initial` into `edited` across the targets: each
    /// torrent gets `(own ∪ added) − removed`, one write per distinct result.
    /// Torrents whose labels would not change, or that are not in the list
    /// (their current labels are unknown), are left alone.
    nonisolated static func labelUpdates(
        _ torrents: [Torrent], ids: [Torrent.ID], initial: Set<String>, edited: [String]
    ) -> [LabelUpdate] {
        let editedSet = Set(edited)
        let added = editedSet.subtracting(initial)
        let removed = initial.subtracting(editedSet)
        let byID = Dictionary(torrents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var groups: [[String]: [Torrent.ID]] = [:]
        for id in ids {
            guard let torrent = byID[id] else { continue }
            let own = Set(torrent.labels)
            let result = own.union(added).subtracting(removed)
            guard result != own else { continue }
            groups[result.sorted(), default: []].append(id)
        }
        return
            groups
            .map { LabelUpdate(labels: $0.key, ids: $0.value) }
            .sorted { $0.labels.lexicographicallyPrecedes($1.labels) }
    }

    private var suggestions: [String] {
        store.list.facets.labels.map(\.name)
    }

    private var subtitle: String {
        ids.count == 1 ? "1 torrent selected" : "\(ids.count) torrents selected"
    }

    private func apply() async {
        guard canApply else { return }
        isSaving = true
        defer { isSaving = false }
        saveError = nil
        let updates = Self.labelUpdates(
            store.list.torrents, ids: ids, initial: initial, edited: tags)
        do {
            for update in updates {
                try await store.actions.setLabels(update.ids, labels: update.labels)
            }
            isPresented = false
        } catch {
            saveError = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview("Edit Labels") {
    let store = TorrentStore(service: MockTorrentService())
    return EditLabelsSheet(isPresented: .constant(true), ids: [2])
        .environment(store)
        .environment(TagColorStore())
        .frame(width: 400)
}
#endif
