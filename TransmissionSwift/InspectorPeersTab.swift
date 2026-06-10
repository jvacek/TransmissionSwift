import SwiftUI
import TransmissionCore

/// Read-only table of connected peers.
struct InspectorPeersTab: View {
    let torrent: Torrent

    var body: some View {
        Table(torrent.peers) {
            TableColumn("Address") { peer in
                HStack(spacing: 6) {
                    if let country = peer.countryCode {
                        Text(country)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.separator))
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
                Text(peer.downloadSpeed.formattedSpeed)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(72)

            TableColumn("Up") { peer in
                Text(peer.uploadSpeed.formattedSpeed)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(64)
        }
        .accessibilityIdentifier("inspector.peers.table")
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
}

#Preview {
    InspectorPeersTab(torrent: Torrent.samples[4])
        .frame(width: 322, height: 400)
}
