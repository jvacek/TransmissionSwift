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
            "Remove \(targets.count) torrent\(targets.count == 1 ? "" : "s") from \(profile.label)"
            + (delete ? " and delete their data?" : "?")
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
                "Removed \(targets.count) torrent\(targets.count == 1 ? "" : "s") from \(profile.label).")
    }
}
