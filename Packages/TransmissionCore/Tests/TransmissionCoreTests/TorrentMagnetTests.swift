// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import TransmissionCore

@Suite("Torrent magnet link")
struct TorrentMagnetTests {
    private func makeTorrent(
        hash: String = "1F0C4D3B2E1A9876FEDC54321089ABCDEF000001",
        name: String = "Ubuntu 24.04 / amd64",
        trackers: [Tracker] = []
    ) -> Torrent {
        Torrent(
            id: 1,
            name: name,
            hash: hash,
            size: 1,
            status: .downloading,
            progress: 0,
            primaryTracker: trackers.first?.host ?? "",
            downloadFolder: "/downloads",
            addedAt: Date(timeIntervalSince1970: 0),
            pieces: 1,
            pieceSize: 1,
            havePieces: 0,
            trackers: trackers)
    }

    private func tracker(_ announce: String) -> Tracker {
        Tracker(
            tier: 0,
            host: "tracker.example",
            announce: announce,
            state: .working,
            statusMessage: "",
            seedCount: 0,
            leechCount: 0,
            downloadCount: 0)
    }

    @Test func magnetUsesLowercasedBtihAndEncodesTheName() {
        #expect(
            makeTorrent().magnetURI
                == "magnet:?xt=urn:btih:1f0c4d3b2e1a9876fedc54321089abcdef000001"
                + "&dn=Ubuntu%2024.04%20/%20amd64")
    }

    @Test func magnetAppendsEveryTrackerAndEncodesQueryDelimiters() {
        let torrent = makeTorrent(trackers: [
            tracker("udp://tracker.example:1337/announce"),
            tracker("https://tracker.example/announce?pass=abc&key=def"),
        ])
        #expect(
            torrent.magnetURI
                == "magnet:?xt=urn:btih:1f0c4d3b2e1a9876fedc54321089abcdef000001"
                + "&dn=Ubuntu%2024.04%20/%20amd64"
                + "&tr=udp://tracker.example:1337/announce"
                + "&tr=https://tracker.example/announce%3Fpass%3Dabc%26key%3Ddef")
    }

    @Test func magnetSkipsEmptyTrackerURLs() {
        let torrent = makeTorrent(trackers: [tracker("")])
        #expect(!torrent.magnetURI.contains("&tr="))
    }
}
