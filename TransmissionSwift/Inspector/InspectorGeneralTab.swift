// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import TransmissionCore

#if DEBUG
import TransmissionTestSupport
#endif

/// Key-value overview of the selected torrent: transfer state up top, then
/// immutable torrent metadata, then location/labels/priority.
struct InspectorGeneralTab: View {
    let torrent: Torrent
    @Environment(TorrentStore.self) private var store
    @Environment(TagColorStore.self) private var tagColors

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                transferSection
                metadataSection
                locationSection
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var transferSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("Transfer"))
                .font(.headline)

            ProgressBar(value: torrent.displayProgress, tint: Color(nsColor: torrent.progressNSColor))

            Text(progressCaption)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error = torrent.errorMessage {
                Label {
                    LinkableText(text: error, color: .red)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.caption)
                .foregroundStyle(.red)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text(L10n.text("State"))
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    statusBadge
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                row(L10n.text("Download"), ColumnFormatters.humanizedSpeed(torrent.downloadSpeed))
                row(L10n.text("Upload"), ColumnFormatters.humanizedSpeed(torrent.uploadSpeed))
                row(L10n.text("Time left"), ColumnFormatters.humanizedETA(torrent.eta, status: torrent.status))
                row(L10n.text("Ratio"), ColumnFormatters.ratio(torrent.ratio))
                row(L10n.text("Peers"), peersSummary)
                row(L10n.text("Downloaded"), ColumnFormatters.humanizedSize(torrent.downloadedEver))
                row(L10n.text("Uploaded"), ColumnFormatters.humanizedSize(torrent.uploadedEver))
                row(
                    L10n.text("Last activity"),
                    torrent.lastActivityAt.map { L10n.relativeDate($0, presentation: .named) } ?? "—")
            }
            .font(.callout)
            .padding(.top, 4)
        }
    }

    /// Immutable facts about the torrent itself — what the .torrent encodes.
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("Metadata"))
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                nameRow
                row(L10n.text("Size"), ColumnFormatters.humanizedSize(torrent.size))
                row(
                    L10n.text("Pieces"),
                    "\(torrent.pieces.formatted()) × \(ColumnFormatters.humanizedSize(torrent.pieceSize))")
                row(L10n.text("Added"), L10n.date(torrent.addedAt, date: .abbreviated, time: .shortened))
                if let createdAt = torrent.createdAt {
                    row(
                        L10n.text("Created"),
                        L10n.date(createdAt, date: .abbreviated, time: .shortened))
                }
                if let creator = torrent.creator {
                    row(L10n.text("Creator"), creator)
                }
                commentRow
                row(L10n.text("Private"), torrent.isPrivate ? L10n.text("Yes") : L10n.text("No"))
                magnetRow
                row(L10n.text("Hash"), torrent.hash, monospaced: true)
            }
            .font(.callout)
        }
    }

    /// Where the data lives and how it's organized — mutable, action-adjacent.
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("Location & Labels"))
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                locationRow
                labelsRow
                priorityRow
                trackerRow
            }
            .font(.callout)
        }
    }

    /// Wraps instead of truncating: the name is the one value worth reading whole.
    private var nameRow: some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(L10n.text("Name"))
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(torrent.name)
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if store.actionsEnabled {
                    Button(L10n.text("Rename…")) {
                        store.openRenameTorrent(for: torrent.id)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .accessibilityLabel(L10n.text("Rename torrent"))
                }
            }
        }
    }

    private var locationRow: some View {
        GridRow {
            Text(L10n.text("Location"))
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            HStack(spacing: 4) {
                Text(locationDisplay)
                    .font(.callout.monospaced())
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(torrent.downloadFolder)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if store.actionsEnabled {
                    Spacer()
                    Button(L10n.text("Set Location…")) {
                        store.openSetLocation(for: [torrent.id])
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .accessibilityLabel(L10n.text("Set location"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Shown relative to the daemon's default download dir when nested inside
    /// it, otherwise the full path (e.g. a folder outside the download root).
    private var locationDisplay: String {
        let relative = relativeDownloadFolder(torrent.downloadFolder, relativeTo: store.list.downloadDirectory)
        if relative.isEmpty { return store.list.downloadDirectory ?? torrent.downloadFolder }
        return relative
    }

    private var statusBadge: some View {
        Text(torrent.status.displayLabel)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(torrent.status.displayColor)
            .background(torrent.status.displayColor.opacity(0.14), in: Capsule())
    }

    private var progressCaption: String {
        let downloaded = Int64(Double(torrent.size) * torrent.progress)
        return L10n.format(
            "%@ of %@ · %@ of %@ pieces",
            ColumnFormatters.humanizedSize(downloaded),
            ColumnFormatters.humanizedSize(torrent.size),
            torrent.havePieces.formatted(),
            torrent.pieces.formatted())
    }

    private var peersSummary: String {
        L10n.format(
            "%@ connected of %@ · %@ seeds",
            torrent.connectedPeerCount.formatted(),
            torrent.availablePeerCount.formatted(),
            torrent.seedCount.formatted())
    }

    private var trackerRow: some View {
        GridRow {
            Text(L10n.text("Tracker"))
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            LinkableText(text: torrent.primaryTracker)
                .font(.callout)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var commentRow: some View {
        GridRow {
            Text(L10n.text("Comment"))
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            if let comment = torrent.comment, !comment.isEmpty {
                LinkableText(text: comment)
                    .font(.callout)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("—")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var magnetRow: some View {
        GridRow {
            Text(L10n.text("Magnet"))
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            if let magnet = torrent.magnetLink {
                Text(magnet)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(magnet)
            } else {
                Text("—")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var labelsRow: some View {
        GridRow {
            Text(L10n.text("Labels"))
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            HStack(spacing: 4) {
                if torrent.labels.isEmpty {
                    Text("—")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(torrent.labels, id: \.self) { label in
                        labelChip(label)
                    }
                }
                if store.actionsEnabled && store.session.supportsLabels {
                    Spacer()
                    Button(L10n.text("Edit…")) {
                        store.openEditLabels(for: [torrent.id])
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .accessibilityLabel(L10n.text("Edit labels"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var priorityRow: some View {
        GridRow {
            Text(L10n.text("Priority"))
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            HStack(spacing: 6) {
                Image(systemName: torrent.priority.systemImage)
                    .foregroundStyle(torrent.priority.displayColor)
                Picker(L10n.text("Priority"), selection: priorityBinding) {
                    ForEach(TorrentPriority.allCases, id: \.self) { priority in
                        Text(priority.displayLabel).tag(priority)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 96, alignment: .leading)
                .disabled(!store.actionsEnabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(L10n.format("Priority: %@", torrent.priority.displayLabel))
        }
    }

    private var priorityBinding: Binding<TorrentPriority> {
        Binding(
            get: { torrent.priority },
            set: { newPriority in
                guard newPriority != torrent.priority else { return }
                Task { await store.actions.setPriority([torrent.id], priority: newPriority) }
            }
        )
    }

    private func labelChip(_ label: String) -> some View {
        TagPill(label: label, color: tagColors.color(for: label))
    }

    private func row(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .font(monospaced ? .callout.monospaced() : .callout)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
#Preview {
    InspectorGeneralTab(torrent: Torrent.samples[4])
        .environment(TorrentStore(service: MockTorrentService()))
        .environment(TagColorStore())
        .frame(width: 322, height: 640)
}
#endif
