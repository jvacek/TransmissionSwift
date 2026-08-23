import SwiftUI
import TransmissionCore

struct TorrentListView: View {
    @Environment(TorrentStore.self) private var store
    @Environment(TagColorStore.self) private var tagColors
    @Environment(ServerProfileStore.self) private var profileStore

    var body: some View {
        let prefs = store.tablePreferences
        return TorrentTableRepresentable(
            rows: store.visibleTorrents,
            selection: Binding(
                get: { store.selectedTorrentIDs },
                set: { store.selectedTorrentIDs = $0 }
            ),
            downloadDirectoryBase: store.downloadDirectory,
            sortColumnID: prefs.sortColumn,
            sortAscending: prefs.sortAscending,
            onSortChange: { column, ascending in
                store.setSortOrder(column: column, ascending: ascending)
            },
            actionsEnabled: store.actionsEnabled,
            labelsSupported: store.supportsLabels,
            tagColors: tagColors.colors,
            onRowAction: { action, ids in
                Task {
                    switch action {
                    case .resume: await store.start(ids)
                    case .pause: await store.stop(ids)
                    case .verify: await store.verify(ids)
                    case .remove: await store.remove(ids)
                    case .removeAndDeleteData:
                        await store.remove(ids, deleteLocalData: true)
                    case .editLabels:
                        store.openEditLabels(for: ids)
                    }
                }
            },
            onInspectorRequest: {
                store.inspectorVisible = true
            },
            mappings: profileStore.activeProfile?.mappings ?? [],
            onOpenMapping: { mapping, ids in
                openMapping(mapping, ids: ids)
            }
        )
        .onAppear {
            restoreSortOrder()
        }
    }

    private func restoreSortOrder() {
        let prefs = store.tablePreferences
        let column = TransmissionCore.TableColumn(rawValue: prefs.sortColumn) ?? .name
        store.setSortOrder(column: column, ascending: prefs.sortAscending)
    }

    private func openMapping(_ mapping: OpenMapping, ids: [Torrent.ID]) {
        guard let torrent = store.torrents.first(where: { ids.contains($0.id) }),
            let profile = profileStore.activeProfile
        else { return }
        Task {
            await MappingOpener.open(
                mapping, torrent: torrent, file: nil, profile: profile, store: store)
        }
    }
}
