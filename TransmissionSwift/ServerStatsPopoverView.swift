// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import TransmissionCore
import TransmissionRPC

/// Popover shown from the status-bar info icon: lifetime ("all time") and
/// current-session transfer statistics from `session-stats`.
struct ServerStatsPopoverView: View {
    @Environment(TorrentStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let stats = store.session.sessionStats {
                section(L10n.text("Current session"), stats.currentStats, showsSessions: false)
                Divider()
                section(L10n.text("All time"), stats.cumulativeStats, showsSessions: true)
            } else {
                Text(L10n.text("Statistics unavailable"))
                    .foregroundStyle(.secondary)
                Text(L10n.text("The server did not report its transfer statistics."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .task { await store.session.refreshSessionStats() }
    }

    private func section(
        _ title: String, _ stats: SessionStats.Stats, showsSessions: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
            row(L10n.text("Downloaded"), ColumnFormatters.humanizedSize(stats.downloadedBytes))
            row(L10n.text("Uploaded"), ColumnFormatters.humanizedSize(stats.uploadedBytes))
            row(L10n.text("Ratio"), ratioText(stats))
            row(L10n.text("Files added"), "\(stats.filesAdded)")
            row(L10n.text("Active time"), ColumnFormatters.humanizedDuration(stats.secondsActive))
            if showsSessions {
                row(L10n.text("Sessions"), "\(stats.sessionCount)")
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
