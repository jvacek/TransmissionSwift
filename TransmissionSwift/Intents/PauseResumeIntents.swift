// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import TransmissionCore

/// Pauses torrents on a server. Leave Torrents empty to pause them all.
struct PauseTorrentsIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Torrents"
    static var description: IntentDescription? {
        IntentDescription(
            "Pauses torrents on a Transmission server. Leave Torrents empty to pause them all.")
    }
    static let openAppWhenRun = false

    @Parameter(title: "Server")
    var server: ServerEntity?

    @Parameter(title: "Torrents")
    var torrents: [TorrentEntity]?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let environment = try AppEnvironment.require()
        let (profile, mutations, targets) = try await environment.mutableTargets(
            server: server, torrents: torrents)
        do {
            try await mutations.stop(targets.map(\.id))
        } catch {
            throw IntentError(message: error.localizedDescription)
        }
        return .result(
            dialog:
                "\(targets.count == 1 ? L10n.format("Paused 1 torrent on %@.", profile.label) : L10n.format("Paused %lld torrents on %@.", Int64(targets.count), profile.label))"
        )
    }
}

/// Resumes torrents on a server. Leave Torrents empty to resume them all.
struct ResumeTorrentsIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Torrents"
    static var description: IntentDescription? {
        IntentDescription(
            "Resumes torrents on a Transmission server. Leave Torrents empty to resume them all.")
    }
    static let openAppWhenRun = false

    @Parameter(title: "Server")
    var server: ServerEntity?

    @Parameter(title: "Torrents")
    var torrents: [TorrentEntity]?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let environment = try AppEnvironment.require()
        let (profile, mutations, targets) = try await environment.mutableTargets(
            server: server, torrents: torrents)
        do {
            try await mutations.start(targets.map(\.id))
        } catch {
            throw IntentError(message: error.localizedDescription)
        }
        return .result(
            dialog:
                "\(targets.count == 1 ? L10n.format("Resumed 1 torrent on %@.", profile.label) : L10n.format("Resumed %lld torrents on %@.", Int64(targets.count), profile.label))"
        )
    }
}
