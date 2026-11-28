// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import TransmissionCore

/// Removes torrents from a server, optionally deleting their downloaded data.
/// Asks for confirmation first.
struct RemoveTorrentsIntent: AppIntent {
    static let title: LocalizedStringResource = "Remove Torrents"
    static var description: IntentDescription? {
        IntentDescription(
            "Removes torrents from a Transmission server, optionally deleting their downloaded data."
        )
    }
    static let openAppWhenRun = false

    @Parameter(title: "Server")
    var server: ServerEntity?

    @Parameter(title: "Torrents")
    var torrents: [TorrentEntity]?

    @Parameter(title: "Also Delete Downloaded Data")
    var deleteData: Bool?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let environment = try AppEnvironment.require()
        let (profile, mutations, targets) = try await environment.mutableTargets(
            server: server, torrents: torrents)

        let delete = deleteData ?? false
        let message =
            targets.count == 1
            ? L10n.format(
                "Remove 1 torrent from %@%@", profile.label, delete ? L10n.text(" and delete its data?") : "?")
            : L10n.format(
                "Remove %lld torrents from %@%@", Int64(targets.count), profile.label,
                delete ? L10n.text(" and delete their data?") : "?")
        try await requestConfirmation(dialog: "\(message)")

        do {
            try await mutations.remove(targets.map(\.id), deleteLocalData: delete)
        } catch {
            throw IntentError(message: error.localizedDescription)
        }
        await SpotlightIndexer.deleteTorrents(
            ids: targets.map { "\(profile.id.uuidString)/\($0.id)" },
            serverID: profile.id.uuidString)
        return .result(
            dialog:
                "\(targets.count == 1 ? L10n.format("Removed 1 torrent from %@.", profile.label) : L10n.format("Removed %lld torrents from %@.", Int64(targets.count), profile.label))"
        )
    }
}
