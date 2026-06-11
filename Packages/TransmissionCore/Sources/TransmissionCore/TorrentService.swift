import Foundation

/// The service-level abstraction the UI consumes. Two implementations live
/// behind this protocol — `MockTorrentService` (used by previews + the
/// `--mock-data` launch arg) and `RPCTorrentService` (real daemon, added in
/// slice 7 of `doc/ui-buildout.md`).
///
/// The view layer never touches `TransmissionClient` directly. That keeps the
/// UI off the wire-protocol shapes and lets us ship the full app skin without
/// extending the RPC surface beyond `session-get`.
public protocol TorrentService: Sendable {
    /// Whether mutation actions (start, stop, remove, add, etc.) are wired up.
    /// False in RPCTorrentService until slice 7b; true in MockTorrentService.
    var supportsActions: Bool { get }

    /// Free space (bytes) on the daemon's download directory, or nil if unknown.
    func freeSpace() async -> Int64?

    /// Initial snapshot. The store calls this once on startup before
    /// subscribing to the live stream.
    func torrents() async throws -> [Torrent]

    /// Live updates. Each emission is the latest full snapshot — diffs are
    /// computed by the UI off the previous value. Unicast: only the store
    /// subscribes. `async` because creating the stream may need to cross into
    /// the service's actor to install the continuation.
    func torrentsStream() async -> AsyncStream<[Torrent]>

    func start(_ ids: [Torrent.ID]) async throws
    func stop(_ ids: [Torrent.ID]) async throws
    /// `deleteLocalData == true` maps to RPC `delete-local-data: true`.
    func remove(_ ids: [Torrent.ID], deleteLocalData: Bool) async throws
    func verify(_ ids: [Torrent.ID]) async throws

    /// Per-file selection. Maps to `torrent-set` `files-wanted` /
    /// `files-unwanted`.
    func setFilesWanted(_ id: Torrent.ID, fileIDs: [TorrentFile.ID], wanted: Bool) async throws

    /// Per-file bandwidth priority. Maps to `torrent-set`
    /// `priority-high` / `priority-normal` / `priority-low`.
    func setFilePriority(_ id: Torrent.ID, fileIDs: [TorrentFile.ID], priority: TorrentPriority)
        async throws

    /// Whole-struct replace of a torrent's transfer options. Maps to one
    /// `torrent-set` call carrying the changed limit fields.
    func setOptions(_ id: Torrent.ID, options: TorrentOptions) async throws

    /// Session-wide alt-speed (turtle) toggle. Reads/writes `session-set`'s
    /// `alt-speed-enabled` field.
    func setAlternativeSpeedEnabled(_ enabled: Bool) async throws
    func isAlternativeSpeedEnabled() async -> Bool

    /// Add a new torrent. Exactly one of `fileURL` / `magnetURL` should be
    /// non-nil. Maps to `torrent-add` in slice 7.
    func add(
        fileURL: URL?,
        magnetURL: String?,
        destination: String,
        label: String?,
        priority: TorrentPriority,
        startWhenAdded: Bool
    ) async throws

    /// Fetch a single torrent with both list fields and inspector fields
    /// (files, fileStats, peers, trackerStats). The returned `Torrent` has
    /// fully-populated `files`, `peers`, and `trackers` arrays. Used by
    /// `TorrentStore` to back the inspector detail pane without merging rich
    /// data into the main list (which gets wiped every poll).
    func inspectorData(for id: Torrent.ID) async throws -> Torrent
}

extension TorrentService {
    public var supportsActions: Bool { true }
    public func freeSpace() async -> Int64? { nil }
}
