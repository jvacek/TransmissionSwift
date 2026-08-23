import SwiftUI
import TransmissionCore

struct TorrentListView: View {
    @Environment(TorrentStore.self) private var store

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
}
