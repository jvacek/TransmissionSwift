import SwiftUI
import TransmissionCore

/// The main torrent Table. Narrow column set per the design's Variant A
/// (~650pt list pane). Slice 2 will widen this when the inspector grows.
struct TorrentListView: View {
    @Environment(TorrentStore.self) private var store

    @AppStorage("sortKeyPath") private var sortKeyPath: String = "name"
    @AppStorage("sortAscending") private var sortAscending: Bool = true
    @State private var sortOrder: [KeyPathComparator<Torrent>] = [KeyPathComparator(\.name)]

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
        // moves many/most rows, and NSTableView's diff/animate cycle becomes
        // quadratic + memory-intensive. A rebuild reloads just visible rows
        // quickly. Selection survives the identity change (lives in store).
        .id(sortOrder)
        .contextMenu(forSelectionType: Torrent.ID.self) { ids in
            contextMenu(for: ids.isEmpty ? store.selectedTorrentIDs : ids)
        } primaryAction: { _ in
            store.inspectorVisible = true
        }
        .accessibilityIdentifier("torrents.table")
        .onAppear {
            sortOrder = [makeComparator(keyPath: sortKeyPath, ascending: sortAscending)]
        }
        .onChange(of: sortOrder) { _, new in
            guard let first = new.first else { return }
            sortKeyPath = keyPathName(first)
            sortAscending = first.order == .forward
        }
    }

    private func makeComparator(keyPath: String, ascending: Bool) -> KeyPathComparator<Torrent> {
        let order: SortOrder = ascending ? .forward : .reverse
        switch keyPath {
        case "size": return KeyPathComparator(\.size, order: order)
        case "progress": return KeyPathComparator(\.progress, order: order)
        case "downloadSpeed": return KeyPathComparator(\.downloadSpeed, order: order)
        case "eta": return KeyPathComparator(\.etaSortKey, order: order)
        case "addedAt": return KeyPathComparator(\.addedAt, order: order)
        case "tracker": return KeyPathComparator(\.primaryTracker, order: order)
        default: return KeyPathComparator(\.name, order: order)
        }
    }

    private func keyPathName(_ comparator: KeyPathComparator<Torrent>) -> String {
        let o = comparator.order
        if comparator == KeyPathComparator(\.size, order: o) { return "size" }
        if comparator == KeyPathComparator(\.progress, order: o) { return "progress" }
        if comparator == KeyPathComparator(\.downloadSpeed, order: o) { return "downloadSpeed" }
        if comparator == KeyPathComparator(\.etaSortKey, order: o) { return "eta" }
        if comparator == KeyPathComparator(\.addedAt, order: o) { return "addedAt" }
        if comparator == KeyPathComparator(\.primaryTracker, order: o) { return "tracker" }
        return "name"
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
