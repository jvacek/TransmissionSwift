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
        let service: any TorrentService
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
    func setConnected(_ service: (any TorrentService)?, for profile: ServerProfile) {
        connection.withLock { state in
            state = service.map { Connection(profileID: profile.id, service: $0) }
        }
    }

    func profiles() -> (profiles: [ServerProfile], activeProfileID: UUID?) {
        ServerProfileStore.readProfiles(from: profileFileURL)
    }

    /// The chosen server, else the active profile, else the first profile.
    func resolve(_ server: ServerEntity?) -> ServerProfile? {
        let loaded = profiles()
        if let server, let match = loaded.profiles.first(where: { $0.id.uuidString == server.id }) {
            return match
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
        profile: ServerProfile, service: any TorrentService
    ) {
        guard let profile = resolve(server) else {
            throw IntentError(
                message: "No Transmission servers are configured. Add one in TransmissionSwift first.")
        }
        guard let service = service(for: profile) else {
            throw IntentError(message: "The server “\(profile.label)” has an invalid RPC address.")
        }
        return (profile, service)
    }

    /// The app's live service when it matches `profile`; otherwise a fresh
    /// factory service. Snapshot replay serves the frozen file, read-only.
    func service(for profile: ServerProfile) -> (any TorrentService)? {
        if let connection = connection.withLock({ $0 }), connection.profileID == profile.id {
            return connection.service
        }
        if mode == .snapshot, let snapshotFileURL {
            return try? SnapshotTorrentService(fileURL: snapshotFileURL)
        }
        return TransmissionServiceFactory.make(for: profile)
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
