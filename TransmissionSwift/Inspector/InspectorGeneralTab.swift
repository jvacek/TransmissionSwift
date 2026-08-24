import SwiftUI
import TransmissionCore

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
            Text("Transfer")
                .font(.headline)

            ProgressBar(value: torrent.progress, status: torrent.status)

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
                    Text("State")
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    statusBadge
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                row("Download", ColumnFormatters.humanizedSpeed(torrent.downloadSpeed))
                row("Upload", ColumnFormatters.humanizedSpeed(torrent.uploadSpeed))
                row("Time left", ColumnFormatters.humanizedETA(torrent.eta, status: torrent.status))
                row("Ratio", torrent.ratio.formatted(.number.precision(.fractionLength(2))))
                row("Peers", peersSummary)
                row("Downloaded", ColumnFormatters.humanizedSize(torrent.downloadedEver))
                row("Uploaded", ColumnFormatters.humanizedSize(torrent.uploadedEver))
                row(
                    "Last activity",
                    torrent.lastActivityAt?.formatted(.relative(presentation: .named)) ?? "—")
            }
            .font(.callout)
            .padding(.top, 4)
        }
    }

    /// Immutable facts about the torrent itself — what the .torrent encodes.
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metadata")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                row("Size", ColumnFormatters.humanizedSize(torrent.size))
                row(
                    "Pieces",
                    "\(torrent.pieces.formatted()) × \(ColumnFormatters.humanizedSize(torrent.pieceSize))")
                row("Added", torrent.addedAt.formatted(date: .abbreviated, time: .shortened))
                if let createdAt = torrent.createdAt {
                    row(
                        "Created",
                        createdAt.formatted(date: .abbreviated, time: .shortened))
                }
                if let creator = torrent.creator {
                    row("Creator", creator)
                }
                commentRow
                row("Private", torrent.isPrivate ? "Yes" : "No")
                magnetRow
                row("Hash", torrent.hash, monospaced: true)
            }
            .font(.callout)
        }
    }

    /// Where the data lives and how it's organized — mutable, action-adjacent.
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Location & Labels")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                row("Location", torrent.downloadFolder, monospaced: true)
                labelsRow
                priorityRow
                trackerRow
            }
            .font(.callout)
        }
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
        return "\(ColumnFormatters.humanizedSize(downloaded)) of \(ColumnFormatters.humanizedSize(torrent.size))"
            + " · \(torrent.havePieces.formatted()) of \(torrent.pieces.formatted()) pieces"
    }

    private var peersSummary: String {
        "\(torrent.connectedPeerCount) connected of \(torrent.availablePeerCount)"
            + " · \(torrent.seedCount) seeds"
    }

    private var trackerRow: some View {
        GridRow {
            Text("Tracker")
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
            Text("Comment")
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
            Text("Magnet")
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
            Text("Labels")
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
                if store.actionsEnabled && store.supportsLabels {
                    Spacer()
                    Button("Edit…") {
                        store.openEditLabels(for: [torrent.id])
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .accessibilityLabel("Edit labels")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var priorityRow: some View {
        GridRow {
            Text("Priority")
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            HStack(spacing: 6) {
                Image(systemName: torrent.priority.systemImage)
                    .foregroundStyle(torrent.priority.displayColor)
                Picker("Priority", selection: priorityBinding) {
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
            .accessibilityLabel("Priority: \(torrent.priority.displayLabel)")
        }
    }

    private var priorityBinding: Binding<TorrentPriority> {
        Binding(
            get: { torrent.priority },
            set: { newPriority in
                guard newPriority != torrent.priority else { return }
                Task { await store.setPriority([torrent.id], priority: newPriority) }
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

#Preview {
    InspectorGeneralTab(torrent: Torrent.samples[4])
        .environment(TorrentStore(service: MockTorrentService()))
        .environment(TagColorStore())
        .frame(width: 322, height: 640)
}
