import AppIntents
import TransmissionCore

/// Re-checks the local data of torrents on a server.
struct VerifyTorrentsIntent: AppIntent {
    static let title: LocalizedStringResource = "Verify Torrents"
    static var description: IntentDescription? {
        IntentDescription(
            "Re-checks the local data of the given torrents on a Transmission server. Torrents is required: verifying a whole large library can stall the daemon."
        )
    }
    static let openAppWhenRun = false

    @Parameter(title: "Server")
    var server: ServerEntity?

    @Parameter(title: "Torrents")
    var torrents: [TorrentEntity]

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let environment = try AppEnvironment.require()
        let (profile, service) = try environment.requireService(server, torrents: torrents)
        guard let mutations = service.mutations else {
            throw IntentError(message: "This server is read-only.")
        }
        let targets = try await TorrentCatalog.targets(torrents, profile: profile, service: service)
        guard !targets.isEmpty else {
            throw IntentError(message: "No matching torrents on \(profile.label).")
        }
        do {
            try await mutations.verify(targets.map(\.id))
        } catch {
            throw IntentError(message: error.localizedDescription)
        }
        return .result(
            dialog:
                "Verifying \(targets.count) torrent\(targets.count == 1 ? "" : "s") on \(profile.label).")
    }
}

/// Asks the trackers for more peers (re-announce).
struct ReannounceTorrentsIntent: AppIntent {
    static let title: LocalizedStringResource = "Re-announce Torrents"
    static var description: IntentDescription? {
        IntentDescription(
            "Asks the trackers for more peers for the given torrents on a Transmission server. Torrents is required: re-announcing a whole large library can stall the daemon."
        )
    }
    static let openAppWhenRun = false

    @Parameter(title: "Server")
    var server: ServerEntity?

    @Parameter(title: "Torrents")
    var torrents: [TorrentEntity]

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let environment = try AppEnvironment.require()
        let (profile, service) = try environment.requireService(server, torrents: torrents)
        guard let mutations = service.mutations else {
            throw IntentError(message: "This server is read-only.")
        }
        let targets = try await TorrentCatalog.targets(torrents, profile: profile, service: service)
        guard !targets.isEmpty else {
            throw IntentError(message: "No matching torrents on \(profile.label).")
        }
        do {
            try await mutations.reannounce(targets.map(\.id))
        } catch {
            throw IntentError(message: error.localizedDescription)
        }
        return .result(
            dialog:
                "Re-announced \(targets.count) torrent\(targets.count == 1 ? "" : "s") on \(profile.label).")
    }
}
