// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import TransmissionCore

/// Small purpose-built torrent for the table unit tests. Deliberately not the
/// curated `MockFixtures` set: each suite's inputs stay explicit and local.
func makeTableTorrent(
    id: Int = 1,
    name: String = "Torrent A",
    size: Int64 = 1_000_000,
    progress: Double = 0.5,
    status: TorrentStatus = .downloading,
    isStopped: Bool = false,
    downloadSpeed: Int64 = 0,
    pieceSize: Int64 = 1,
    options: TorrentOptions = TorrentOptions(),
    labels: [String] = [],
    priority: TorrentPriority = .normal,
    queuePosition: Int? = nil,
    errorMessage: String? = nil,
    files: [TorrentFile] = []
) -> Torrent {
    Torrent(
        id: id,
        name: name,
        hash: "hash-\(id)",
        size: size,
        status: status,
        isStopped: isStopped,
        progress: progress,
        downloadSpeed: downloadSpeed,
        primaryTracker: "tracker",
        downloadFolder: "/downloads",
        addedAt: Date(timeIntervalSince1970: 1_700_000_000),
        labels: labels,
        priority: priority,
        pieces: 10,
        pieceSize: pieceSize,
        havePieces: 5,
        queuePosition: queuePosition,
        errorMessage: errorMessage,
        options: options,
        files: files)
}
