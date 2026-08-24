/// Interface to a remote Transmission daemon.
///
/// The app and core layers depend on this protocol rather than a concrete
/// implementation, so tests can substitute a fake client.
public protocol TransmissionClient: Sendable {
    func sessionGet() async throws(TransmissionError) -> SessionInfo
    func torrentGet(fields: [String], ids: [Int]?) async throws(TransmissionError) -> TorrentGetResponse

    /// Send `torrent-start`, `torrent-stop`, or `torrent-verify` for the given IDs.
    func torrentAction(_ method: String, ids: [Int]) async throws(TransmissionError)
    func torrentRemove(ids: [Int], deleteLocalData: Bool) async throws(TransmissionError)
    func torrentSet(_ args: TorrentSetArguments) async throws(TransmissionError)
    func torrentAdd(_ args: TorrentAddArguments) async throws(TransmissionError) -> TorrentAddResponse
    func sessionSet(_ args: SessionSetArguments) async throws(TransmissionError)

    /// Whether the peer listening port is reachable from the outside
    /// (`port-test` returns `port-is-open`).
    func portTest() async throws(TransmissionError) -> Bool
}
