import Foundation

/// The service-level abstraction the UI consumes. Two implementations live
/// behind this protocol — `MockTorrentService` (used by previews and the empty
/// no-server state) and `RPCTorrentService` (real daemon, added in slice 7 of
/// `doc/ui-buildout.md`).
///
/// The view layer never touches `TransmissionClient` directly. That keeps the
/// UI off the wire-protocol shapes and lets us ship the full app skin without
/// extending the RPC surface beyond `session-get`.
public protocol TorrentService: Sendable {
    /// Whether mutation actions (start, stop, remove, add, etc.) are wired up.
    /// False in RPCTorrentService until slice 7b; true in MockTorrentService.
    var supportsActions: Bool { get }

    /// Whether the daemon supports labels (rpc-version >= 17, Transmission 4.0).
    /// The RPC service derives this from its cached `session-get`; mock/replay
    /// report true (the mock supports labels, and replay is read-only anyway).
    func supportsLabels() async -> Bool

    /// Free space (bytes) on the daemon's download directory, or nil if unknown.
    func freeSpace() async -> Int64?

    /// Default download directory on the daemon host, or nil if unknown. Must be
    /// a protocol requirement (not extension-only) so calls through `any
    /// TorrentService` dynamically dispatch to the concrete override.
    func downloadDirectory() async -> String?

    /// Initial snapshot. The store calls this once on startup before
    /// subscribing to the live stream.
    func torrents() async throws -> [Torrent]

    /// Live updates. Each emission is the latest full snapshot — diffs are
    /// computed by the UI off the previous value. Unicast: only the store
    /// subscribes. `async` because creating the stream may need to cross into
    /// the service's actor to install the continuation.
    func torrentsStream() async -> AsyncThrowingStream<[Torrent], Error>

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

    /// Whole-set replace of one or more torrents' labels (empty array clears
    /// them). Maps to `torrent-set` `labels`; Transmission replaces the full
    /// set, it never appends.
    func setLabels(_ ids: [Torrent.ID], labels: [String]) async throws

    /// Session-wide alt-speed (turtle) toggle. Reads/writes `session-set`'s
    /// `alt-speed-enabled` field.
    func setAlternativeSpeedEnabled(_ enabled: Bool) async throws
    func isAlternativeSpeedEnabled() async -> Bool

    /// The current session-level settings (speed limits, network, queue, seed
    /// ratio/idle). Returns nil when disconnected or unknown. Read-only services
    /// (mock with no state, snapshot replay) return a plausible value so previews
    /// and the no-server placeholder render populated controls.
    func sessionSettings() async -> SessionSettings?

    /// Applies a partial `session-set` write. Default no-op for read-only /
    /// snapshot services; `RPCTorrentService` maps the patch and sends it.
    func applySessionSettings(_ patch: SessionSettingsPatch) async throws

    /// Add a new torrent. Exactly one of `fileURL` / `magnetURL` should be
    /// non-nil. Maps to `torrent-add` in slice 7.
    func add(
        fileURL: URL?,
        magnetURL: String?,
        destination: String,
        labels: [String],
        priority: TorrentPriority,
        startWhenAdded: Bool
    ) async throws

    /// Fetch a single torrent with both list fields and inspector fields
    /// (files, fileStats, peers, trackerStats). The returned `Torrent` has
    /// fully-populated `files`, `peers`, and `trackers` arrays. Used by
    /// `TorrentStore` to back the inspector detail pane without merging rich
    /// data into the main list (which gets wiped every poll).
    func inspectorData(for id: Torrent.ID) async throws -> Torrent

    /// Fetch the full daemon state (session + every torrent with list and
    /// inspector fields) as an unredacted wire-shaped snapshot. Only
    /// `RPCTorrentService` implements this; mock / replay services throw
    /// `SnapshotError.captureUnsupported`.
    func captureRawSnapshot() async throws -> SnapshotFile
}

extension TorrentService {
    public var supportsActions: Bool { true }
    public func supportsLabels() async -> Bool { true }
    public func freeSpace() async -> Int64? { nil }
    public func downloadDirectory() async -> String? { nil }
    public func sessionSettings() async -> SessionSettings? { nil }
    public func applySessionSettings(_ patch: SessionSettingsPatch) async throws {}
    public func captureRawSnapshot() async throws -> SnapshotFile {
        throw SnapshotError.captureUnsupported
    }
}
