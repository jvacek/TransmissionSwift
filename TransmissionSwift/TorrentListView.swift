import SwiftUI
import TransmissionCore

struct TorrentListView: View {
    @Environment(TorrentStore.self) private var store

    @State private var columnCustomization = TableColumnCustomization<Torrent>()
    @State private var sortOrder: [KeyPathComparator<Torrent>] = [KeyPathComparator(\Torrent.name)]

    private static let columnCustomizationKey = "columnCustomization"

    private func persistColumnCustomization() {
        guard let encoded = try? JSONEncoder().encode(columnCustomization) else { return }
        UserDefaults.standard.set(encoded, forKey: Self.columnCustomizationKey)
    }

    private func loadColumnCustomization() {
        guard let data = UserDefaults.standard.data(forKey: Self.columnCustomizationKey),
            let decoded = try? JSONDecoder().decode(TableColumnCustomization<Torrent>.self, from: data)
        else { return }
        columnCustomization = decoded
    }

    private var rows: [Torrent] {
        store.visibleTorrents
    }

    var body: some View {
        @Bindable var store = store

        let nameColumn =
            TableColumn("Name", value: \Torrent.name) { torrent in
                nameCell(torrent)
            }
            .width(min: 240, ideal: 400, max: 800)
            .customizationID(TableColumn.name.rawValue)
            .defaultVisibility(.visible)

        let sizeColumn =
            TableColumn("Size", value: \Torrent.size) { torrent in
                sizeCell(torrent)
            }
            .width(min: 54, ideal: 74, max: 120)
            .customizationID(TableColumn.size.rawValue)
            .defaultVisibility(.visible)

        let progressColumn =
            TableColumn("Progress", value: \Torrent.progress) { torrent in
                progressCell(torrent)
            }
            .width(min: 80, ideal: 130, max: 200)
            .customizationID(TableColumn.progress.rawValue)
            .defaultVisibility(.visible)

        let downSpeedColumn =
            TableColumn("\u{2193} Speed", value: \Torrent.downloadSpeed) { torrent in
                downloadSpeedCell(torrent)
            }
            .width(min: 70, ideal: 95, max: 130)
            .customizationID(TableColumn.downloadSpeed.rawValue)
            .defaultVisibility(.visible)

        let upSpeedColumn =
            TableColumn("\u{2191} Speed", value: \Torrent.uploadSpeed) { torrent in
                uploadSpeedCell(torrent)
            }
            .width(min: 70, ideal: 95, max: 130)
            .customizationID(TableColumn.uploadSpeed.rawValue)
            .defaultVisibility(.visible)

        let etaColumn =
            TableColumn("ETA", value: \Torrent.etaSortKey) { torrent in
                etaCell(torrent)
            }
            .width(min: 52, ideal: 66, max: 100)
            .customizationID(TableColumn.eta.rawValue)
            .defaultVisibility(.visible)

        let ratioColumn =
            TableColumn("Ratio", value: \Torrent.ratio) { torrent in
                ratioCell(torrent)
            }
            .width(min: 50, ideal: 60, max: 90)
            .customizationID(TableColumn.ratio.rawValue)
            .defaultVisibility(.visible)

        let addedColumn =
            TableColumn("Added", value: \Torrent.addedAt) { torrent in
                addedCell(torrent)
            }
            .width(min: 72, ideal: 100, max: 150)
            .customizationID(TableColumn.addedAt.rawValue)
            .defaultVisibility(.visible)

        let trackerColumn =
            TableColumn("Tracker", value: \Torrent.primaryTracker) { torrent in
                trackerCell(torrent)
            }
            .width(min: 80, ideal: 120, max: 200)
            .customizationID(TableColumn.primaryTracker.rawValue)
            .defaultVisibility(.visible)

        let peersColumn =
            TableColumn("Peers", value: \Torrent.connectedPeerCount) { torrent in
                peersCell(torrent)
            }
            .width(min: 50, ideal: 65, max: 100)
            .customizationID(TableColumn.connectedPeers.rawValue)
            .defaultVisibility(.hidden)

        let availColumn =
            TableColumn("Available", value: \Torrent.availablePeerCount) { torrent in
                availablePeersCell(torrent)
            }
            .width(min: 60, ideal: 80, max: 110)
            .customizationID(TableColumn.availablePeers.rawValue)
            .defaultVisibility(.hidden)

        let seedsColumn =
            TableColumn("Seeds", value: \Torrent.seedCount) { torrent in
                seedsCell(torrent)
            }
            .width(min: 45, ideal: 60, max: 90)
            .customizationID(TableColumn.seeds.rawValue)
            .defaultVisibility(.hidden)

        let statusColumn =
            TableColumn("Status", value: \Torrent.status.rawValue) { torrent in
                statusCell(torrent)
            }
            .width(min: 80, ideal: 100, max: 150)
            .customizationID(TableColumn.status.rawValue)
            .defaultVisibility(.hidden)

        let labelColumn =
            TableColumn("Label", value: \Torrent.labelSortKey) { torrent in
                labelCell(torrent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 80, ideal: 120, max: 200)
            .customizationID(TableColumn.label.rawValue)
            .defaultVisibility(.hidden)

        let priorityColumn =
            TableColumn("Priority", value: \Torrent.priority.rawValue) { torrent in
                priorityCell(torrent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .width(min: 70, ideal: 90, max: 130)
            .customizationID(TableColumn.priority.rawValue)
            .defaultVisibility(.hidden)

        let queueColumn =
            TableColumn("Queue", value: \Torrent.queuePositionSortKey) { torrent in
                queueCell(torrent)
            }
            .width(min: 50, ideal: 65, max: 100)
            .customizationID(TableColumn.queuePosition.rawValue)
            .defaultVisibility(.hidden)

        let errorColumn =
            TableColumn("Error", value: \Torrent.errorMessageSortKey) { torrent in
                errorCell(torrent)
            }
            .width(min: 100, ideal: 200, max: 400)
            .customizationID(TableColumn.errorMessage.rawValue)
            .defaultVisibility(.hidden)

        let piecesColumn =
            TableColumn("Pieces", value: \Torrent.havePieces) { torrent in
                piecesCell(torrent)
            }
            .width(min: 70, ideal: 90, max: 130)
            .customizationID(TableColumn.pieces.rawValue)
            .defaultVisibility(.hidden)

        let folderColumn =
            TableColumn("Folder", value: \Torrent.downloadFolder) { torrent in
                folderCell(torrent)
            }
            .width(min: 120, ideal: 200, max: 400)
            .customizationID(TableColumn.downloadFolder.rawValue)
            .defaultVisibility(.hidden)

        let hashColumn =
            TableColumn("Hash", value: \Torrent.hash) { torrent in
                hashCell(torrent)
            }
            .width(min: 100, ideal: 200, max: 400)
            .customizationID(TableColumn.hash.rawValue)
            .defaultVisibility(.hidden)

        return Table(
            rows, selection: $store.selectedTorrentIDs, sortOrder: $sortOrder,
            columnCustomization: $columnCustomization
        ) {
            Group {
                nameColumn
                sizeColumn
                progressColumn
                downSpeedColumn
                upSpeedColumn
                etaColumn
                ratioColumn
                addedColumn
                trackerColumn
                peersColumn
            }
            Group {
                availColumn
                seedsColumn
                statusColumn
                labelColumn
                priorityColumn
                queueColumn
                errorColumn
                piecesColumn
                folderColumn
                hashColumn
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .tableColumnHeaders(.automatic)
        .id(sortOrder)
        .contextMenu(forSelectionType: Torrent.ID.self) { ids in
            contextMenu(for: ids.isEmpty ? store.selectedTorrentIDs : ids)
        } primaryAction: { _ in
            store.inspectorVisible = true
        }
        .accessibilityIdentifier("torrents.table")
        .onAppear {
            loadColumnCustomization()
            restoreSortOrder()
        }
        .onChange(of: sortOrder) { _, new in
            guard let first = new.first else { return }
            store.setSortOrder(new)
        }
        .onChange(of: columnCustomization) {
            persistColumnCustomization()
        }
    }

    private func restoreSortOrder() {
        let prefs = store.tablePreferences
        let column = TableColumn(rawValue: prefs.sortColumn) ?? .name
        sortOrder = [column.comparator(order: prefs.sortAscending ? .forward : .reverse)]
        store.setSortOrder(sortOrder)
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
        Button("Remove\u{2026}", systemImage: "trash", role: .destructive) {
            Task { await store.remove(idArray) }
        }
        .disabled(!store.actionsEnabled)
        Button("Remove and Delete Data\u{2026}", systemImage: "trash.fill", role: .destructive) {
            Task { await store.remove(idArray, deleteLocalData: true) }
        }
        .disabled(!store.actionsEnabled)
    }
}

extension TorrentListView {
    // MARK: - Table Cell Functions

    @ViewBuilder
    fileprivate func nameCell(_ torrent: Torrent) -> some View {
        HStack(spacing: 6) {
            StatusDot(status: torrent.status)
            Text(torrent.name)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    fileprivate func sizeCell(_ torrent: Torrent) -> some View {
        Text(ColumnFormatters.humanizedSize(torrent.size))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    fileprivate func progressCell(_ torrent: Torrent) -> some View {
        ProgressBar(value: torrent.progress, status: torrent.status)
    }

    @ViewBuilder
    fileprivate func downloadSpeedCell(_ torrent: Torrent) -> some View {
        ColumnFormatters.speedView(torrent.downloadSpeed, color: .blue)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    fileprivate func uploadSpeedCell(_ torrent: Torrent) -> some View {
        ColumnFormatters.speedView(torrent.uploadSpeed, color: .green)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    fileprivate func etaCell(_ torrent: Torrent) -> some View {
        Text(ColumnFormatters.humanizedETA(torrent.eta, status: torrent.status))
            .monospacedDigit()
            .foregroundStyle(ColumnFormatters.etaColor(for: torrent.status))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    fileprivate func ratioCell(_ torrent: Torrent) -> some View {
        let (text, color) = ColumnFormatters.ratioTextAndColor(torrent.ratio)
        Text(text)
            .monospacedDigit()
            .foregroundStyle(color ?? .secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    fileprivate func addedCell(_ torrent: Torrent) -> some View {
        Text(ColumnFormatters.relativeDate(torrent.addedAt))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .help(torrent.addedAt.formatted(date: .abbreviated, time: .complete))
    }

    @ViewBuilder
    fileprivate func trackerCell(_ torrent: Torrent) -> some View {
        Group {
            if torrent.primaryTracker.isEmpty {
                Text("\u{2014}")
                    .foregroundStyle(.tertiary)
            } else {
                Text(torrent.primaryTracker)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    fileprivate func peersCell(_ torrent: Torrent) -> some View {
        Text("\(torrent.connectedPeerCount)/\(torrent.availablePeerCount)")
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    fileprivate func availablePeersCell(_ torrent: Torrent) -> some View {
        Group {
            if torrent.availablePeerCount > 0 {
                Text("\(torrent.availablePeerCount)")
                    .foregroundStyle(.secondary)
            } else {
                Text("\u{2014}")
                    .foregroundStyle(.tertiary)
            }
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    fileprivate func seedsCell(_ torrent: Torrent) -> some View {
        Group {
            if torrent.seedCount > 0 {
                Text("\(torrent.seedCount)")
                    .foregroundStyle(.secondary)
            } else {
                Text("\u{2014}")
                    .foregroundStyle(.tertiary)
            }
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    fileprivate func statusCell(_ torrent: Torrent) -> some View {
        let (color, text) = ColumnFormatters.statusContent(torrent.status)
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    fileprivate func labelCell(_ torrent: Torrent) -> some View {
        if let label = torrent.label, !label.isEmpty {
            Text(label)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.primary)
        } else {
            Text("\u{2014}")
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    fileprivate func priorityCell(_ torrent: Torrent) -> some View {
        ColumnFormatters.priorityView(torrent.priority)
    }

    @ViewBuilder
    fileprivate func queueCell(_ torrent: Torrent) -> some View {
        Group {
            if torrent.queuePosition != nil {
                Text(ColumnFormatters.queuePosition(torrent.queuePosition))
                    .foregroundStyle(.orange)
            } else {
                Text("\u{2014}")
                    .foregroundStyle(.tertiary)
            }
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    fileprivate func errorCell(_ torrent: Torrent) -> some View {
        Group {
            if let error = torrent.errorMessage, !error.isEmpty {
                Text(error)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.red)
                    .help(error)
            } else {
                Text("\u{2014}")
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    fileprivate func piecesCell(_ torrent: Torrent) -> some View {
        Text(ColumnFormatters.piecesText(have: torrent.havePieces, total: torrent.pieces))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    fileprivate func folderCell(_ torrent: Torrent) -> some View {
        let displayPath = ColumnFormatters.truncatedPath(torrent.downloadFolder, relativeTo: store.downloadDirectory)
        Text(displayPath)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .help(torrent.downloadFolder)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    fileprivate func hashCell(_ torrent: Torrent) -> some View {
        Text(torrent.hash)
            .monospaced()
            .foregroundStyle(.secondary)
            .help(torrent.hash)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
