import SwiftUI
import TransmissionCore

/// Tracker announce endpoints grouped by failover tier, one `GroupBox` card
/// per tracker.
struct InspectorTrackersTab: View {
    let torrent: Torrent

    private var tiers: [(tier: Int, trackers: [Tracker])] {
        Dictionary(grouping: torrent.trackers, by: \.tier)
            .sorted { $0.key < $1.key }
            .map { (tier: $0.key, trackers: $0.value) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(tiers, id: \.tier) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        if tiers.count > 1 {
                            Text("Tier \(group.tier + 1)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(group.trackers) { tracker in
                            TrackerCard(tracker: tracker)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TrackerCard: View {
    let tracker: Tracker

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(tracker.state.displayColor)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel(tracker.state.displayLabel)
                    Text(tracker.host)
                        .font(.callout.weight(.semibold).monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(tracker.statusMessage)
                    .font(.caption)
                    .foregroundStyle(tracker.state == .error ? Color.red : Color.secondary)
                Text(statsLine)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statsLine: String {
        "\(tracker.seedCount) seeds · \(tracker.leechCount) leechers"
            + " · \(tracker.downloadCount.formatted()) downloads"
    }
}

#Preview {
    InspectorTrackersTab(torrent: Torrent.samples[4])
        .frame(width: 322, height: 500)
}
