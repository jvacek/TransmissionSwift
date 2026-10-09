import Foundation
import Synchronization
import TransmissionCore

/// Process-wide state the app shares with its App Intents.
///
/// App Intents run in the app's process but outside the SwiftUI object graph, so
/// they can't see `TorrentStore`/`ServerProfileStore` through the environment.
/// This is the narrow shared surface they need: which server profiles exist, and
/// the service the app is (or would be) talking to. It deliberately holds no UI
/// state — selection, filters and polling stay in `TorrentStore`.
///
/// Registering the app's own instance is what makes `--snapshot` replay (and any
/// future seeded mode) deterministic for intents too: they resolve against the
/// same ephemeral profiles and frozen service the app booted with, not the real
/// `servers.json` + network.
nonisolated final class AppEnvironment: Sendable {
    enum Mode: Sendable {
        /// Real profiles from Application Support; services come from the factory.
        case live
        /// Read-only replay of a captured snapshot file.
        case snapshot
    }

    let mode: Mode
    /// The file the app's `ServerProfileStore` uses. The real Application Support
    /// file in live mode; an ephemeral temp file under `--snapshot` /
    /// `--ephemeral-profiles`.
    let profileFileURL: URL
    /// The captured snapshot file, when replaying one.
    let snapshotFileURL: URL?

    private struct Connection: Sendable {
        let profileID: ServerProfile.ID
        let service: any TorrentReading
    }
    private let connection: Mutex<Connection?>

    init(mode: Mode, profileFileURL: URL, snapshotFileURL: URL? = nil) {
        self.mode = mode
        self.profileFileURL = profileFileURL
        self.snapshotFileURL = snapshotFileURL
        self.connection = Mutex(nil)
    }

    /// Records the service the app is connected with, so an intent targeting the
    /// same profile reuses the live connection instead of opening a second one.
    func setConnected(_ service: (any TorrentReading)?, for profile: ServerProfile) {
        connection.withLock { state in
            state = service.map { Connection(profileID: profile.id, service: $0) }
        }
    }

    /// Forgets the recorded service once the app disconnects, so an intent can't
    /// reuse a connection the app no longer considers live.
    func clearConnection() {
        connection.withLock { $0 = nil }
    }

    func profiles() -> (profiles: [ServerProfile], activeProfileID: UUID?) {
        ServerProfileStore.readProfiles(from: profileFileURL)
    }

    /// A profile by its id, for resolving entity identifiers that carry a server
    /// UUID without the caller having a `ServerEntity` to hand.
    func profile(withID id: UUID) -> ServerProfile? {
        profiles().profiles.first { $0.id == id }
    }

    /// The chosen server, else the active profile, else the first profile.
    ///
    /// A supplied server that no longer matches a profile resolves to nil rather
    /// than silently falling back to a different one: for a mutating intent that
    /// would act on the wrong daemon. Callers that must report the failure treat
    /// nil as an error (`requireService`).
    func resolve(_ server: ServerEntity?) -> ServerProfile? {
        let loaded = profiles()
        if let server {
            return loaded.profiles.first { $0.id.uuidString == server.id }
        }
        if let id = loaded.activeProfileID,
            let match = loaded.profiles.first(where: { $0.id == id })
        {
            return match
        }
        return loaded.profiles.first
    }

    /// The chosen server plus a usable service, or a user-facing error. Shared
    /// by the action intents.
    func requireService(_ server: ServerEntity?) throws -> (
        profile: ServerProfile, service: any TorrentReading
    ) {
        guard let profile = resolve(server) else {
            throw IntentError(message: Self.missingServerMessage(server))
        }
        return (profile, try resolvedService(for: profile))
    }

    /// The error for a server that can't be resolved. A named server that no
    /// longer exists is distinct from having none configured at all, and must
    /// not be silently replaced by the active profile.
    private static func missingServerMessage(_ server: ServerEntity?) -> String {
        if server != nil {
            return "That server is no longer configured. Pick another one in the shortcut."
        }
        return "No Transmission servers are configured. Add one in TransmissionSwift first."
    }

    /// The chosen server, else the server the given torrents belong to, else the
    /// active profile. Deriving from the torrents means a Shortcut that resolves
    /// a `transmissionswift://` link doesn't also have to set the Server field.
    func requireService(_ server: ServerEntity?, torrents: [TorrentEntity]?) throws -> (
        profile: ServerProfile, service: any TorrentReading
    ) {
        try requireService(server ?? self.server(for: torrents))
    }

    /// The mutation half of a resolved service, or a user-facing error when the
    /// source is read-only (snapshot replay).
    func requireMutations(_ service: any TorrentReading) throws -> any TorrentMutating {
        guard let mutations = service.mutations else {
            throw IntentError(message: "This server is read-only.")
        }
        return mutations
    }

    /// Resolves the server, its mutation service and the torrents an action
    /// should target — the shared preamble of every mutating intent. Throws a
    /// user-facing error when the server is read-only or nothing matches.
    func mutableTargets(
        server: ServerEntity?, torrents: [TorrentEntity]?
    ) async throws -> (
        profile: ServerProfile, mutations: any TorrentMutating, targets: [Torrent]
    ) {
        let (profile, service) = try requireService(server, torrents: torrents)
        let mutations = try requireMutations(service)
        let targets = try await TorrentCatalog.targets(torrents, profile: profile, service: service)
        guard !targets.isEmpty else {
            throw IntentError(message: "No matching torrents on \(profile.label).")
        }
        return (profile, mutations, targets)
    }

    /// The profile the given torrents belong to, when they name one that still
    /// exists. The server UUID is baked into the entity, so this needs no picker.
    private func server(for torrents: [TorrentEntity]?) -> ServerEntity? {
        guard let id = torrents?.first?.serverID, let uuid = UUID(uuidString: id),
            let profile = profile(withID: uuid)
        else { return nil }
        return ServerEntity(profile: profile)
    }

    /// The app's live service when it matches `profile`; otherwise a fresh
    /// factory service. Snapshot replay serves the frozen file, read-only.
    /// Best-effort — resolution failures return nil (used by the entity pickers).
    func service(for profile: ServerProfile) -> (any TorrentReading)? {
        try? resolvedService(for: profile)
    }

    /// Like `service(for:)`, but reports why resolution failed so an action can
    /// show the real cause instead of a generic error.
    func resolvedService(for profile: ServerProfile) throws -> any TorrentReading {
        if let connection = connection.withLock({ $0 }), connection.profileID == profile.id {
            return connection.service
        }
        if mode == .snapshot, let snapshotFileURL {
            guard let service = try? SnapshotTorrentService(fileURL: snapshotFileURL) else {
                throw IntentError(message: "Couldn't read the snapshot file.")
            }
            return service
        }
        do {
            return try TransmissionServiceFactory.make(for: profile)
        } catch {
            throw IntentError(message: Self.serviceFailureMessage(error, server: profile.label))
        }
    }

    private static func serviceFailureMessage(_ error: any Error, server: String) -> String {
        switch error {
        case TransmissionServiceFactory.Failure.invalidRPCURL:
            return "The server “\(server)” has an invalid RPC address."
        case TransmissionServiceFactory.Failure.keychain:
            return "Couldn't read the saved password for “\(server)”. Unlock your Keychain and try again."
        default:
            return "Couldn't connect to “\(server)”."
        }
    }
}

// MARK: - Process-wide registration

nonisolated extension AppEnvironment {
    private static let box = Mutex<AppEnvironment?>(nil)

    /// Called once from `TransmissionSwiftApp.init`. Intents and entity queries
    /// read it back through `current`.
    static func register(_ environment: AppEnvironment) {
        box.withLock { $0 = environment }
    }

    static var current: AppEnvironment? {
        box.withLock { $0 }
    }

    /// `current`, or a user-facing error when the app hasn't registered yet.
    static func require() throws -> AppEnvironment {
        guard let environment = current else {
            throw IntentError(message: "TransmissionSwift isn't ready. Open the app and try again.")
        }
        return environment
    }
}
