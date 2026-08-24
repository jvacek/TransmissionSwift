import Foundation
import TransmissionRPC

/// A frozen, read-only `TorrentService` backed by a snapshot file captured
/// from a real daemon (see `doc/snapshot-replay.md`). Launched with the
/// `--snapshot <path>` app argument.
///
/// Decodes the wire-shaped envelope through the same types (`SessionInfo`,
/// `WireTorrent`) and the same `Torrent(wire:)` mapping as a live poll, then
/// serves the state with no network. The stream yields the list once and
/// closes — there is nothing to tick. Mutations are unavailable
/// (`supportsActions == false`).
public actor SnapshotTorrentService: TorrentService {
    private let session: SessionInfo
    private let domainTorrents: [Torrent]
    private let colors: [String: TagColor]

    public init(fileURL: URL) throws {
        let data = try Data(contentsOf: fileURL)
        let file = try JSONDecoder().decode(SnapshotFile.self, from: data)
        guard file.version == snapshotFormatVersion else {
            throw SnapshotError.unsupportedVersion(file.version)
        }
        self.session = file.session
        self.domainTorrents = file.torrents.map { Torrent(wire: $0) }
        self.colors = file.tagColors ?? [:]
    }

    /// Tag→colour assignments captured with the snapshot, for seeding the
    /// replay's `TagColorStore` so colours render identically to the capture.
    public nonisolated var tagColors: [String: TagColor] { colors }

    // MARK: - TorrentService

    public nonisolated var supportsActions: Bool { false }

    public func freeSpace() async -> Int64? { session.downloadDirFreeSpace }

    public func downloadDirectory() async -> String? { session.downloadDir }

    public func torrents() async throws -> [Torrent] { domainTorrents }

    public func torrentsStream() -> AsyncThrowingStream<[Torrent], Error> {
        let (stream, continuation) = AsyncThrowingStream<[Torrent], Error>.makeStream()
        continuation.yield(domainTorrents)
        continuation.finish()
        return stream
    }

    public func inspectorData(for id: Torrent.ID) async throws -> Torrent {
        guard let torrent = domainTorrents.first(where: { $0.id == id }) else {
            throw SnapshotError.torrentNotFound(id)
        }
        return torrent
    }

    public func isAlternativeSpeedEnabled() async -> Bool { session.altSpeedEnabled }

    /// Read-only: the captured session's settings, so the Speed/Network panes
    /// render the frozen values.
    public func sessionSettings() async -> SessionSettings? { SessionSettings(wire: session) }

    public func applySessionSettings(_ patch: SessionSettingsPatch) async throws {
        throw SnapshotError.replayReadOnly
    }

    // Mutations are unreachable (supportsActions == false, so the UI disables
    // them); throwing guards against accidental invocation from code that
    // doesn't consult `supportsActions`.
    public func start(_ ids: [Torrent.ID]) async throws { throw SnapshotError.replayReadOnly }
    public func stop(_ ids: [Torrent.ID]) async throws { throw SnapshotError.replayReadOnly }
    public func remove(_ ids: [Torrent.ID], deleteLocalData: Bool) async throws {
        throw SnapshotError.replayReadOnly
    }
    public func verify(_ ids: [Torrent.ID]) async throws { throw SnapshotError.replayReadOnly }
    public func reannounce(_ ids: [Torrent.ID]) async throws { throw SnapshotError.replayReadOnly }
    public func setFilesWanted(_ id: Torrent.ID, fileIDs: [TorrentFile.ID], wanted: Bool)
        async throws
    {
        throw SnapshotError.replayReadOnly
    }
    public func setFilePriority(
        _ id: Torrent.ID, fileIDs: [TorrentFile.ID], priority: TorrentPriority
    ) async throws {
        throw SnapshotError.replayReadOnly
    }
    public func setPriority(_ ids: [Torrent.ID], priority: TorrentPriority) async throws {
        throw SnapshotError.replayReadOnly
    }
    public func setOptions(_ id: Torrent.ID, options: TorrentOptions) async throws {
        throw SnapshotError.replayReadOnly
    }
    public func setLabels(_ ids: [Torrent.ID], labels: [String]) async throws {
        throw SnapshotError.replayReadOnly
    }
    public func setAlternativeSpeedEnabled(_ enabled: Bool) async throws {
        throw SnapshotError.replayReadOnly
    }
    public func add(
        fileURL: URL?, magnetURL: String?, destination: String, labels: [String],
        priority: TorrentPriority, startWhenAdded: Bool
    ) async throws {
        throw SnapshotError.replayReadOnly
    }
}
