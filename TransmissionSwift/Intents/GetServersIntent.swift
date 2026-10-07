import AppIntents
import TransmissionCore

/// Returns the configured servers as entities, so a shortcut can choose one or
/// loop over them.
struct GetServersIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Servers"
    static var description: IntentDescription? {
        IntentDescription(
            "Returns the Transmission servers configured in the app, so a shortcut can pick one or loop over them."
        )
    }
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<[ServerEntity]> & ProvidesDialog {
        let environment = try AppEnvironment.require()
        let profiles = environment.profiles().profiles
        let servers = profiles.map(ServerEntity.init(profile:))
        await SpotlightIndexer.indexServers(profiles)
        let dialog =
            servers.isEmpty
            ? "No Transmission servers are configured."
            : "\(servers.count) server\(servers.count == 1 ? "" : "s")."
        return .result(value: servers, dialog: "\(dialog)")
    }
}
