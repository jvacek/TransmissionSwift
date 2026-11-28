// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

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
            ? L10n.text("No Transmission servers are configured.")
            : servers.count == 1
                ? L10n.text("1 server.")
                : L10n.format("%lld servers.", Int64(servers.count))
        return .result(value: servers, dialog: "\(dialog)")
    }
}
