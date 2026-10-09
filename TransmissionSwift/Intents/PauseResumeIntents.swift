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
                "Paused \(targets.count) torrent\(targets.count == 1 ? "" : "s") on \(profile.label).")
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
                "Resumed \(targets.count) torrent\(targets.count == 1 ? "" : "s") on \(profile.label).")
    }
}
