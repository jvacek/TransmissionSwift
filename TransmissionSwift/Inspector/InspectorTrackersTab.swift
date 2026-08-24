import SwiftUI
import TransmissionCore

/// Tracker announce endpoints grouped by failover tier, one `GroupBox` card
/// per tracker.
struct InspectorTrackersTab: View {
    let torrent: Torrent
    @Environment(FaviconStore.self) private var favicons

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
        // Make sure icons exist for this torrent's trackers — no-op for hosts
        // the sidebar already fetched.
        .task(id: torrent.id) {
            let hosts = Set(torrent.trackers.map(\.host))
            guard !hosts.isEmpty else { return }
            await favicons.refresh(hosts: Array(hosts))
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
                    FaviconView(host: tracker.host)
                        .frame(width: 16, height: 16)
                    Text(tracker.host)
                        .font(.callout.weight(.semibold).monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LinkableText(
                    text: tracker.statusMessage,
                    color: tracker.state == .error ? Color.red : Color.secondary
                )
                .font(.caption)
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
        .environment(FaviconStore())
        .frame(width: 322, height: 500)
}
