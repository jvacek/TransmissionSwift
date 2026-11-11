import SwiftUI
import TransmissionCore

struct TorrentListView: View {
    @Environment(TorrentStore.self) private var store
    @Environment(TagColorStore.self) private var tagColors
    @Environment(ServerProfileStore.self) private var profileStore
    @Environment(OpenMappingStore.self) private var mappingStore

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
                store.perform(action, ids: ids)
            },
            onInspectorRequest: {
                store.inspector.isVisible = true
            },
            mappings: profileStore.activeProfile.map { mappingStore.mappings(for: $0) } ?? [],
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
                mappingStore: mappingStore)
        }
    }
}

extension TorrentStore {
    /// Runs a torrent action for `ids`. The row context menu, the Torrent menu
    /// and its keyboard shortcuts all funnel through here so they cannot drift.
    func perform(_ action: TorrentRowAction, ids: [Torrent.ID]) {
        switch action {
        case .resume: Task { await actions.start(ids) }
        case .pause: Task { await actions.stop(ids) }
        case .setPriority(let priority): Task { await actions.setPriority(ids, priority: priority) }
        case .verify: Task { await actions.verify(ids) }
        case .reannounce: Task { await actions.reannounce(ids) }
        case .remove: actions.requestRemove(ids)
        case .removeAndDeleteData: actions.requestRemove(ids, deleteLocalData: true)
        case .editLabels: openEditLabels(for: ids)
        case .setLocation: openSetLocation(for: ids)
        case .rename: if let id = ids.first { openRenameTorrent(for: id) }
        }
    }
}
