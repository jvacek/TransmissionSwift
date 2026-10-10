import SwiftUI
import TransmissionCore
import TransmissionTestSupport

/// Read-only table of connected peers.
struct InspectorPeersTab: View {
    let torrent: Torrent

    @Environment(GeoIPStore.self) private var geoip

    var body: some View {
        Table(torrent.peers) {
            TableColumn("Address") { peer in
                HStack(spacing: 6) {
                    if let code = countryCode(for: peer), let flag = countryFlagEmoji(for: code) {
                        Text(flag)
                            .font(.title3)
                            .accessibilityLabel(code)
                    }
                    Text(peer.ipAddress)
                        .font(.callout.monospaced())
                }
            }
            .width(min: 130)

            TableColumn("Client") { peer in
                Text(peer.client)
                    .foregroundStyle(.secondary)
            }
            .width(min: 90)

            TableColumn("Flags") { peer in
                Text(peer.flags)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
            .width(52)

            TableColumn("%") { peer in
                Text("\(Int(peer.progress * 100))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(36)

            TableColumn("Down") { peer in
                Text(ColumnFormatters.humanizedSpeed(peer.downloadSpeed))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(72)

            TableColumn("Up") { peer in
                Text(ColumnFormatters.humanizedSpeed(peer.uploadSpeed))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(64)
        }
        .accessibilityIdentifier("inspector.peers.table")
        .task(id: torrent.peers.map(\.ipAddress)) {
            await geoip.resolve(torrent.peers)
        }
        .overlay {
            if torrent.peers.isEmpty {
                ContentUnavailableView(
                    "No Peers",
                    systemImage: "person.2.slash",
                    description: Text("No peers are connected right now.")
                )
            }
        }
    }

    /// The GeoIP result wins when resolved; mock/snapshot fixtures may carry a
    /// code directly.
    private func countryCode(for peer: Peer) -> String? {
        geoip.code(for: peer.ipAddress) ?? peer.countryCode
    }
}

#Preview {
    InspectorPeersTab(torrent: Torrent.samples[4])
        .environment(GeoIPStore())
        .frame(width: 322, height: 400)
}
