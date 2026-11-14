// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import TransmissionCore

#if DEBUG
import TransmissionTestSupport
#endif

/// Read-only table of connected peers.
struct InspectorPeersTab: View {
    let torrent: Torrent

    @Environment(GeoIPStore.self) private var geoip

    var body: some View {
        // Sized for the inspector's default width: client and flags ride under
        // the address and both speeds share a column, so the numbers never
        // scroll off to the right.
        Table(torrent.peers) {
            TableColumn("Peer") { peer in
                HStack(spacing: 6) {
                    if let code = countryCode(for: peer), let flag = countryFlagEmoji(for: code) {
                        Text(flag)
                            .font(.title3)
                            .accessibilityLabel(code)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(peer.ipAddress)
                            .font(.callout.monospaced())
                        Text(Self.detail(for: peer))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                }
                .help(Self.detail(for: peer))
            }
            .width(min: 120)

            TableColumn("%") { peer in
                Text(peer.progress, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(40)

            TableColumn("Speed") { peer in
                VStack(alignment: .trailing, spacing: 1) {
                    Text("↓ \(ColumnFormatters.humanizedSpeed(peer.downloadSpeed))")
                    Text("↑ \(ColumnFormatters.humanizedSpeed(peer.uploadSpeed))")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .monospacedDigit()
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "Down \(ColumnFormatters.humanizedSpeed(peer.downloadSpeed)), "
                        + "up \(ColumnFormatters.humanizedSpeed(peer.uploadSpeed))")
            }
            .width(84)
        }
        .accessibilityIdentifier("inspector.peers.table")
        .task(id: torrent.peers.map(\.ipAddress)) {
            await geoip.resolve(torrent.peers)
        }
        .onChange(of: geoip.enabled) {
            Task { await geoip.resolve(torrent.peers) }
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

    /// "Client · flags", or whichever of the two the peer reported.
    nonisolated static func detail(for peer: Peer) -> String {
        [peer.client, peer.flags].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The GeoIP result wins when resolved; mock/snapshot fixtures may carry a
    /// code directly.
    private func countryCode(for peer: Peer) -> String? {
        geoip.code(for: peer.ipAddress) ?? peer.countryCode
    }
}

#if DEBUG
#Preview {
    InspectorPeersTab(torrent: Torrent.samples[4])
        .environment(GeoIPStore())
        .frame(width: 322, height: 400)
}
#endif
