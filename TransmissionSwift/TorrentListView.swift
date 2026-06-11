import SwiftUI
import TransmissionCore

/// The main torrent Table. Narrow column set per the design's Variant A
/// (~650pt list pane). Slice 2 will widen this when the inspector grows.
struct TorrentListView: View {
    @Environment(TorrentStore.self) private var store

    /// In-memory sort. Persisting "last sort" across launches is a slice 4+
    /// concern (`@AppStorage`); for now we keep it on the view.
    @State private var sortOrder: [KeyPathComparator<Torrent>] = [
        KeyPathComparator(\.name)
    ]

    private var rows: [Torrent] {
        store.visibleTorrents.sorted(using: sortOrder)
    }

    var body: some View {
        @Bindable var store = store
        Table(rows, selection: $store.selectedTorrentIDs, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { torrent in
                HStack(spacing: 6) {
                    StatusDot(status: torrent.status)
                    Text(torrent.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .width(min: 240, ideal: 400)
            TableColumn("Size", value: \.size) { torrent in
                Text(torrent.size.formattedSize)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 54, ideal: 74)
            TableColumn("Progress", value: \.progress) { torrent in
                ProgressBar(value: torrent.progress, status: torrent.status)
            }
            .width(min: 80, ideal: 130)
            TableColumn("Down", value: \.downloadSpeed) { torrent in
                Text(torrent.downloadSpeed.formattedSpeed)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 78)
            TableColumn("ETA", value: \.etaSortKey) { torrent in
                Text(torrent.eta.formattedETA)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 52, ideal: 66)
            TableColumn("Added", value: \.addedAt) { torrent in
                Text(torrent.addedAt.formattedDate)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 72, ideal: 100)
            TableColumn("Tracker", value: \.primaryTracker) { torrent in
                Text(torrent.primaryTracker.isEmpty ? "—" : torrent.primaryTracker)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 120)
        }
        // Default axes for this modifier is .vertical only, so the previous
        // pass left horizontal at its (bouncy) default. Vertical stays
        // automatic — the user wants that bounce to persist when the list
        // overflows the window.
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        // Changing the sort rebuilds the table instead of diffing it. A re-sort
        // moves nearly every row, and NSTableView applies that as per-row moves
        // — quadratic, and a multi-second beachball at a few hundred rows. A
        // rebuild is a plain reload of the visible rows. Selection lives in the
        // store, so it survives the identity change.
        .id(sortOrder)
        .contextMenu(forSelectionType: Torrent.ID.self) { ids in
            contextMenu(for: ids.isEmpty ? store.selectedTorrentIDs : ids)
        } primaryAction: { _ in
            store.inspectorVisible = true
        }
        .accessibilityIdentifier("torrents.table")
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<Torrent.ID>) -> some View {
        let idArray = Array(ids)
        Button("Resume", systemImage: "play.fill") {
            Task { await store.start(idArray) }
        }
        .disabled(!store.actionsEnabled)
        Button("Pause", systemImage: "pause.fill") {
            Task { await store.stop(idArray) }
        }
        .disabled(!store.actionsEnabled)
        Divider()
        Button("Verify Local Data", systemImage: "checkmark.shield") {
            Task { await store.verify(idArray) }
        }
        .disabled(!store.actionsEnabled)
        Divider()
        Button("Remove…", systemImage: "trash", role: .destructive) {
            Task { await store.remove(idArray) }
        }
        .disabled(!store.actionsEnabled)
        Button("Remove and Delete Data…", systemImage: "trash.fill", role: .destructive) {
            Task { await store.remove(idArray, deleteLocalData: true) }
        }
        .disabled(!store.actionsEnabled)
    }
}

extension Torrent {
    /// Sortable key for the ETA column. nil (paused/error/queued) and .infinity
    /// (seeding forever) both sort to the bottom — there's no meaningful order
    /// between them, so we collapse them to the same large value.
    fileprivate var etaSortKey: TimeInterval { eta ?? .infinity }
}
