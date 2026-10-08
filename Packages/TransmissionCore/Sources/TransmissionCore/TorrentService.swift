import Foundation
import TransmissionRPC

/// Read access to one daemon: its torrent list, inspector data and session
/// state. Implemented by every service, including the read-only snapshot replay.
///
/// The store and the view layer depend on this, never on `TransmissionClient`.
/// Declaring reads and mutations separately lets a read-only source (snapshot
/// replay) implement only what it can actually do, instead of stubbing every
/// mutation.
public protocol TorrentReading: Sendable {
    /// Whether the daemon supports labels (rpc-version >= 17, Transmission 4.0).
    /// The RPC service derives this from its cached `session-get`; mock/replay
    /// report true. Default true.
    func supportsLabels() async -> Bool

    /// Free space (bytes) on the daemon's download directory, or nil if unknown.
    /// Default nil.
    func freeSpace() async -> Int64?

    /// Default download directory on the daemon host, or nil if unknown. Must be
    /// a protocol requirement (not extension-only) so calls through `any
    /// TorrentReading` dynamically dispatch to the concrete override.
    func downloadDirectory() async -> String?

    /// Initial snapshot. The store calls this once on startup before
    /// subscribing to the live stream.
    func torrents() async throws -> [Torrent]

    /// Live updates. Each emission is the latest full snapshot — diffs are
    /// computed by the UI off the previous value. Unicast: only the store
    /// subscribes. `async` because creating the stream may need to cross into
    /// the service's actor to install the continuation.
    func torrentsStream() async -> AsyncThrowingStream<[Torrent], Error>

    /// Session-wide alt-speed (turtle) state. Reads `session-set`'s
    /// `alt-speed-enabled` field.
    func isAlternativeSpeedEnabled() async -> Bool

    /// The current session-level settings (speed limits, network, queue, seed
    /// ratio/idle). Returns nil when disconnected or unknown. Read-only services
    /// (mock with no state, snapshot replay) return a plausible value so previews
    /// and the no-server placeholder render populated controls. Default nil.
    func sessionSettings() async -> SessionSettings?

    /// The daemon's long version string (e.g. `"4.1.2 (f234716f3e)"`), or nil
    /// when unknown (mock / disconnected / not yet polled). Used to pre-fill
    /// the bug-report template. Default nil.
    func daemonVersion() async -> String?

    /// Whether the daemon's peer port is reachable from the outside (`port-test`).
    /// Returns nil when the service can't answer (read-only/snapshot services or
    /// a transient failure). Default nil.
    func isPortOpen() async -> Bool?

    /// Current + lifetime transfer statistics (`session-stats`). Returns nil
    /// when the service can't answer (mock/replay services or a transient
    /// failure). Default nil.
    func sessionStats() async -> SessionStats?

    /// Fetch a single torrent with both list fields and inspector fields
    /// (files, fileStats, peers, trackerStats). The returned `Torrent` has
    /// fully-populated `files`, `peers`, and `trackers` arrays. Used by
    /// `TorrentStore` to back the inspector detail pane without merging rich
    /// data into the main list (which gets wiped every poll).
    func inspectorData(for id: Torrent.ID) async throws -> Torrent

    /// Fetch the full daemon state (session + every torrent with list and
    /// inspector fields) as an unredacted wire-shaped snapshot. Only
    /// `RPCTorrentService` implements this; mock / replay services rely on the
    /// default, which throws `SnapshotError.captureUnsupported`.
    func captureRawSnapshot() async throws -> SnapshotFile
}

extension TorrentReading {
    public func supportsLabels() async -> Bool { true }
    public func freeSpace() async -> Int64? { nil }
    public func downloadDirectory() async -> String? { nil }
    public func sessionSettings() async -> SessionSettings? { nil }
    public func daemonVersion() async -> String? { nil }
    public func isPortOpen() async -> Bool? { nil }
    public func sessionStats() async -> SessionStats? { nil }

    /// The mutation half of a service, when it has one. Read-only sources
    /// (snapshot replay) return nil. Resolving it here gives callers one lookup
    /// instead of a repeated `self as? any TorrentMutating` at every action site.
    public var mutations: (any TorrentMutating)? { self as? any TorrentMutating }

    public func captureRawSnapshot() async throws -> SnapshotFile {
        throw SnapshotError.captureUnsupported
    }
}

/// Mutation access to one daemon. Live and mock services implement this; the
/// read-only snapshot replay does not. A caller resolves it with
/// `reading.mutations`.
public protocol TorrentMutating: Sendable {
    func start(_ ids: [Torrent.ID]) async throws
    func stop(_ ids: [Torrent.ID]) async throws
    /// `deleteLocalData == true` maps to RPC `delete-local-data: true`.
    func remove(_ ids: [Torrent.ID], deleteLocalData: Bool) async throws
    func verify(_ ids: [Torrent.ID]) async throws

    /// Re-announce the given torrents to their trackers. Maps to RPC
    /// `torrent-reannounce` ("ask tracker for more peers").
    func reannounce(_ ids: [Torrent.ID]) async throws

    /// Per-file selection. Maps to `torrent-set` `files-wanted` /
    /// `files-unwanted`.
    func setFilesWanted(_ id: Torrent.ID, fileIDs: [TorrentFile.ID], wanted: Bool) async throws

    /// Per-file bandwidth priority. Maps to `torrent-set`
    /// `priority-high` / `priority-normal` / `priority-low`.
    func setFilePriority(_ id: Torrent.ID, fileIDs: [TorrentFile.ID], priority: TorrentPriority)
        async throws

    /// Whole-torrent bandwidth priority. Maps to `torrent-set`
    /// `bandwidthPriority` (-1 = low, 0 = normal, 1 = high).
    func setPriority(_ ids: [Torrent.ID], priority: TorrentPriority) async throws

    /// Whole-struct replace of a torrent's transfer options. Maps to one
    /// `torrent-set` call carrying the changed limit fields.
    func setOptions(_ id: Torrent.ID, options: TorrentOptions) async throws

    /// Apply a partial speed-limit change to one or more torrents in a single
    /// `torrent-set`. Only the non-nil fields of `patch` are sent, so each
    /// torrent's other options are preserved.
    func setSpeedLimits(_ ids: [Torrent.ID], _ patch: TorrentSpeedLimitPatch) async throws

    /// Whole-set replace of one or more torrents' labels (empty array clears
    /// them). Maps to `torrent-set` `labels`; Transmission replaces the full
    /// set, it never appends.
    func setLabels(_ ids: [Torrent.ID], labels: [String]) async throws

    /// Change the download location of one or more torrents on the daemon host.
    /// `move == true` relocates the existing data to `location`; `move == false`
    /// only repoints the torrent (for data moved out-of-band). Maps to RPC
    /// `torrent-set-location`; the daemon treats the path as on its own host,
    /// not the Mac running this app.
    func setLocation(_ ids: [Torrent.ID], location: String, move: Bool) async throws

    /// Rename a file/folder inside a torrent. Maps 1:1 to RPC
    /// `torrent-rename-path` (which requires exactly one torrent id). For a
    /// root rename pass the torrent's current name as `path` and the new
    /// single-component name as `newName`.
    func renamePath(_ id: Torrent.ID, path: String, newName: String) async throws

    /// Session-wide alt-speed (turtle) toggle. Writes `session-set`'s
    /// `alt-speed-enabled` field.
    func setAlternativeSpeedEnabled(_ enabled: Bool) async throws

    /// Applies a partial `session-set` write.
    func applySessionSettings(_ patch: SessionSettingsPatch) async throws

    /// Add a new torrent. Exactly one of `fileURL` / `magnetURL` should be
    /// non-nil. Maps to `torrent-add`.
    func add(
        fileURL: URL?,
        magnetURL: String?,
        destination: String,
        labels: [String],
        priority: TorrentPriority,
        startWhenAdded: Bool
    ) async throws
}

/// A service that both reads and mutates — the full set of capabilities a live
/// daemon connection offers. `MockTorrentService` and `RPCTorrentService`
/// conform; `SnapshotTorrentService` is read-only and conforms only to
/// `TorrentReading`.
public protocol TorrentService: TorrentReading, TorrentMutating {}
