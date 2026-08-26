import SwiftUI
import TransmissionCore
import TransmissionRPC

/// Popover shown from the status-bar info icon: lifetime ("all time") and
/// current-session transfer statistics from `session-stats`.
struct ServerStatsPopoverView: View {
    @Environment(TorrentStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let stats = store.sessionStats {
                section("Current session", stats.currentStats)
                Divider()
                section("All time", stats.cumulativeStats)
            } else {
                Text("Statistics unavailable")
                    .foregroundStyle(.secondary)
                Text("The server did not report its transfer statistics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .task { await store.refreshSessionStats() }
    }

    private func section(_ title: String, _ stats: SessionStats.Stats) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
            row("Downloaded", ColumnFormatters.humanizedSize(stats.downloadedBytes))
            row("Uploaded", ColumnFormatters.humanizedSize(stats.uploadedBytes))
            row("Ratio", ratioText(stats))
            row("Files added", "\(stats.filesAdded)")
            row("Active time", ColumnFormatters.humanizedDuration(stats.secondsActive))
            if title == "All time" {
                row("Sessions", "\(stats.sessionCount)")
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .monospacedDigit()
        }
    }

    private func ratioText(_ stats: SessionStats.Stats) -> String {
        guard stats.downloadedBytes > 0 else { return "\u{2014}" }
        let ratio = Double(stats.uploadedBytes) / Double(stats.downloadedBytes)
        return String(format: "%.2f", ratio)
    }
}
