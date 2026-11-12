// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import AppKit
import TransmissionCore

/// Opens TransmissionSwift showing a specific torrent — the action Spotlight and
/// Siri use to open an indexed torrent, and a shortcut's way to deep-link into
/// the app.
struct OpenTorrentIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Torrent"
    static var description: IntentDescription? {
        IntentDescription("Opens TransmissionSwift showing a torrent.")
    }
    static let openAppWhenRun = true

    @Parameter(title: "Torrent")
    var target: TorrentEntity

    func perform() async throws -> some IntentResult {
        let serverID = UUID(uuidString: target.serverID)
        await MainActor.run {
            OpenRequestBus.shared.request = OpenRequest(serverID: serverID, torrentID: target.torrentID)
            NSApplication.shared.activate()
        }
        return .result()
    }
}
