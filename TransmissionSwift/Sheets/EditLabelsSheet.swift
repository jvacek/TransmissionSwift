// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import TransmissionCore
import TransmissionTestSupport

/// Dedicated popup for editing a torrent's labels. Prefills with the union of
/// the target set's labels, so a bulk edit keeps every existing label, and
/// applies via `store.actions.setLabels` — which replaces the full set on every
/// targeted torrent, matching Transmission's `torrent-set labels` semantics.
struct EditLabelsSheet: View {
    @Environment(TorrentStore.self) private var store
    @Binding var isPresented: Bool
    let ids: [Torrent.ID]

    @State private var tags: [String] = []
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Labels")
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            TagsInputField(tags: $tags, suggestions: suggestions)
                .disabled(!store.actionsEnabled)

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(isSaving ? "Applying…" : "Apply") {
                    Task { await apply() }
                }
                .buttonStyle(.glassProminent)
                .disabled(isSaving || !store.actionsEnabled)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { tags = initialLabels }
    }

    private var initialLabels: [String] {
        Self.mergedLabels(store.list.torrents, ids: ids)
    }

    /// Union of the selection's labels. An intersection would silently drop
    /// every label not shared by all targets when the edited set replaces the
    /// full set on apply.
    nonisolated static func mergedLabels(_ torrents: [Torrent], ids: [Torrent.ID]) -> [String] {
        let wanted = Set(ids)
        return Set(torrents.lazy.filter { wanted.contains($0.id) }.flatMap(\.labels)).sorted()
    }

    private var suggestions: [String] {
        store.list.facets.labels.map(\.name)
    }

    private var subtitle: String {
        ids.count == 1 ? "1 torrent selected" : "\(ids.count) torrents selected"
    }

    private func apply() async {
        isSaving = true
        defer { isSaving = false }
        await store.actions.setLabels(ids, labels: tags)
        isPresented = false
    }
}

#Preview("Edit Labels") {
    let store = TorrentStore(service: MockTorrentService())
    return EditLabelsSheet(isPresented: .constant(true), ids: [2])
        .environment(store)
        .environment(TagColorStore())
        .frame(width: 400)
}
