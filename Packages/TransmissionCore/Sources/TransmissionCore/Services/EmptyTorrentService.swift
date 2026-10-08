import Foundation
import TransmissionRPC

/// The no-daemon `TorrentReading` used before a server is connected (and when a
/// snapshot file fails to load). Returns no torrents, a plausible session so the
/// settings panes render populated controls, and never ticks.
///
/// This is the production stand-in that replaces reusing the test mock as the
/// "no server" service.
public struct EmptyTorrentService: TorrentReading {
    public init() {}

    public func torrents() async throws -> [Torrent] { [] }

    /// Yields one empty snapshot and stays open, mirroring the previous
    /// placeholder: there is no daemon to poll, and finishing the stream would
    /// end the store's poll loop instead of leaving it waiting.
    public func torrentsStream() -> AsyncThrowingStream<[Torrent], Error> {
        AsyncThrowingStream { continuation in
            continuation.yield([])
        }
    }

    public func isAlternativeSpeedEnabled() async -> Bool { false }

    /// `SessionSettings.sample` so the settings panes render populated controls.
    public func sessionSettings() async -> SessionSettings? { .sample }

    /// The placeholder previously reported the port reachable.
    public func isPortOpen() async -> Bool? { true }

    public func inspectorData(for id: Torrent.ID) async throws -> Torrent {
        throw TransmissionError.serverError("No server connected")
    }
}
