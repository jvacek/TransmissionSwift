import SwiftUI
import TransmissionCore

struct TorrentListView: View {
    @Environment(TorrentStore.self) private var store
    @Environment(TagColorStore.self) private var tagColors
    @Environment(ServerProfileStore.self) private var profileStore

    var body: some View {
        let prefs = store.list.tablePreferences
        return TorrentTableRepresentable(
            rows: store.list.visibleTorrents,
            selection: Binding(
                get: { store.list.selectedTorrentIDs },
                set: { store.list.selectedTorrentIDs = $0 }
            ),
            downloadDirectoryBase: store.list.downloadDirectory,
            sortColumnID: prefs.sortColumn,
            sortAscending: prefs.sortAscending,
            onSortChange: { column, ascending in
                store.list.setSortOrder(column: column, ascending: ascending)
            },
            actionsEnabled: store.actionsEnabled,
            labelsSupported: store.session.supportsLabels,
            tagColors: tagColors.colors,
            onRowAction: { action, ids in
                Task {
                    switch action {
                    case .resume: await store.actions.start(ids)
                    case .pause: await store.actions.stop(ids)
                    case .setPriority(let priority): await store.actions.setPriority(ids, priority: priority)
                    case .verify: await store.actions.verify(ids)
                    case .reannounce: await store.actions.reannounce(ids)
                    case .remove: store.actions.requestRemove(ids)
                    case .removeAndDeleteData:
                        store.actions.requestRemove(ids, deleteLocalData: true)
                    case .editLabels:
                        store.openEditLabels(for: ids)
                    case .setLocation:
                        store.openSetLocation(for: ids)
                    case .rename:
                        if let id = ids.first { store.openRenameTorrent(for: id) }
                    }
                }
            },
            onInspectorRequest: {
                store.inspector.isVisible = true
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
        let prefs = store.list.tablePreferences
        let column = TransmissionCore.TableColumn(rawValue: prefs.sortColumn) ?? .name
        store.list.setSortOrder(column: column, ascending: prefs.sortAscending)
    }

    private func openMapping(_ mapping: OpenMapping, ids: [Torrent.ID]) {
        guard let torrent = store.list.torrents.first(where: { ids.contains($0.id) }),
            let profile = profileStore.activeProfile
        else { return }
        Task {
            await MappingOpener.open(
                mapping, torrent: torrent, file: nil, profile: profile, store: store,
                profileStore: profileStore)
        }
    }
}
