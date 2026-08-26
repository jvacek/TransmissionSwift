/// The `session-stats` response (RPC spec §4.2): current and cumulative
/// transfer totals. Cumulative counts survive daemon restarts; the
/// `current-stats` block covers only the running session.
public struct SessionStats: Codable, Sendable, Equatable {
    public let activeTorrentCount: Int
    public let downloadSpeed: Int64
    public let pausedTorrentCount: Int
    public let torrentCount: Int
    public let uploadSpeed: Int64
    /// Totals since the daemon was first installed.
    public let cumulativeStats: Stats
    /// Totals for the currently running daemon process.
    public let currentStats: Stats

    enum CodingKeys: String, CodingKey {
        case activeTorrentCount
        case downloadSpeed
        case pausedTorrentCount
        case torrentCount
        case uploadSpeed
        case cumulativeStats = "cumulative-stats"
        case currentStats = "current-stats"
    }

    /// One `tr_session_stats` block: bytes transferred, files added, how many
    /// daemon sessions contributed, and total seconds the daemon was up.
    public struct Stats: Codable, Sendable, Equatable {
        public let uploadedBytes: Int64
        public let downloadedBytes: Int64
        public let filesAdded: Int
        public let sessionCount: Int
        public let secondsActive: Int64
    }
}
