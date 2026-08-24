import SwiftUI
import TransmissionCore

/// Dedicated popup for editing a torrent's labels. Prefills with the labels
/// common to the whole target set (empty when the selection shares none) and
/// applies via `store.setLabels` — which replaces the full set on every
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
        let selected = store.torrents.filter { ids.contains($0.id) }
        guard let first = selected.first else { return [] }
        return selected.dropFirst().reduce(first.labels) { common, torrent in
            common.filter(torrent.labels.contains)
        }
    }

    private var suggestions: [String] {
        store.facets.labels.map(\.name)
    }

    private var subtitle: String {
        ids.count == 1 ? "1 torrent selected" : "\(ids.count) torrents selected"
    }

    private func apply() async {
        isSaving = true
        defer { isSaving = false }
        await store.setLabels(ids, labels: tags)
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
