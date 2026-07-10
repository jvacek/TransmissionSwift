import SwiftUI
import TransmissionCore

/// Key-value overview of the selected torrent: transfer state up top,
/// immutable details below.
struct InspectorGeneralTab: View {
    let torrent: Torrent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                transferSection
                detailsSection
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
                Label(error, systemImage: "exclamationmark.triangle")
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
            }
            .font(.callout)
            .padding(.top, 4)
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                row("Size", ColumnFormatters.humanizedSize(torrent.size))
                row(
                    "Pieces",
                    "\(torrent.pieces.formatted()) × \(ColumnFormatters.humanizedSize(torrent.pieceSize))")
                row("Added", torrent.addedAt.formatted(date: .abbreviated, time: .shortened))
                row("Location", torrent.downloadFolder, monospaced: true)
                row("Label", torrent.label ?? "—")
                row("Priority", torrent.priority.displayLabel)
                row("Tracker", torrent.primaryTracker)
                row("Hash", torrent.hash, monospaced: true)
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
        .frame(width: 322, height: 640)
}
