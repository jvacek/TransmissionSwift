import Foundation
import Testing
import TransmissionCore
import TransmissionTestSupport

@testable import TransmissionSwift

/// The connection flow's branches, with the Keychain, the service factory and
/// `AppEnvironment` injected — no daemon, no real Keychain, no global state.
@Suite("ConnectionCoordinator")
@MainActor
struct ConnectionCoordinatorTests {
    private struct Boom: Error {}

    private func makeStore() -> TorrentStore {
        TorrentStore(service: MockTorrentService(initial: []))
    }

    private func makeEnvironment() -> AppEnvironment {
        AppEnvironment(
            mode: .live,
            profileFileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("conn-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent("servers.json"))
    }

    private func disconnectedReason(_ state: ConnectionState) -> String? {
        if case .disconnected(let reason) = state { return reason }
        return nil
    }

    @Test("skips the connect flow under Xcode's test host / previews")
    func skipsUnderAuxiliaryProcess() async {
        var built = false
        let coordinator = ConnectionCoordinator(
            store: makeStore(),
            environment: makeEnvironment(),
            isAuxiliaryProcess: true,
            readCredentials: { _ in nil },
            makeService: { _, _ in
                built = true
                return nil
            })

        await coordinator.connect(to: ServerProfile(label: "S", host: "host.local"))

        #expect(!built)
    }

    @Test("a second connect to the same connected profile is a no-op")
    func idempotentWhenAlreadyConnected() async {
        let store = makeStore()
        let profile = ServerProfile(label: "S", host: "host.local")
        let mock = MockTorrentService(initial: [])
        var builds = 0
        let coordinator = ConnectionCoordinator(
            store: store,
            environment: makeEnvironment(),
            isAuxiliaryProcess: false,
            readCredentials: { _ in nil },
            makeService: { _, _ in
                builds += 1
                return mock
            })

        await coordinator.connect(to: profile)
        store.simulateConnection(.connected)
        await coordinator.connect(to: profile)

        #expect(builds == 1)
    }

    @Test("a Keychain read failure reports the saved-password error")
    func keychainFailureIsReported() async {
        let store = makeStore()
        let profile = ServerProfile(label: "S", host: "host.local", username: "user")
        let coordinator = ConnectionCoordinator(
            store: store,
            environment: makeEnvironment(),
            isAuxiliaryProcess: false,
            readCredentials: { _ in throw Boom() },
            makeService: { _, _ in nil })

        await coordinator.connect(to: profile)

        #expect(disconnectedReason(store.connection)?.contains("Keychain") == true)
    }

    @Test("an invalid address reports the invalid-URL error")
    func invalidAddressIsReported() async {
        let store = makeStore()
        let coordinator = ConnectionCoordinator(
            store: store,
            environment: makeEnvironment(),
            isAuxiliaryProcess: false,
            readCredentials: { _ in nil },
            makeService: { _, _ in nil })

        await coordinator.connect(to: ServerProfile(label: "S", host: "host.local"))

        #expect(disconnectedReason(store.connection) == "Invalid server URL")
    }

    @Test("a successful connect installs the service and shares it with App Intents")
    func successSharesService() async {
        let store = makeStore()
        let environment = makeEnvironment()
        let profile = ServerProfile(label: "S", host: "host.local")
        let mock = MockTorrentService(initial: [])
        let coordinator = ConnectionCoordinator(
            store: store,
            environment: environment,
            isAuxiliaryProcess: false,
            readCredentials: { _ in nil },
            makeService: { _, _ in mock })

        await coordinator.connect(to: profile)

        #expect((environment.service(for: profile) as? MockTorrentService) === mock)
    }

    @Test("a disconnect clears the shared App Intents connection")
    func disconnectClearsSharedConnection() {
        let environment = makeEnvironment()
        let profile = ServerProfile(label: "S", host: "host.local")
        let mock = MockTorrentService(initial: [])
        environment.setConnected(mock, for: profile)
        let coordinator = ConnectionCoordinator(
            store: makeStore(),
            environment: environment,
            isAuxiliaryProcess: false,
            readCredentials: { _ in nil },
            makeService: { _, _ in nil })

        coordinator.connectionStateChanged(.disconnected(reason: "offline"))

        #expect((environment.service(for: profile) as? MockTorrentService) == nil)
    }
}
