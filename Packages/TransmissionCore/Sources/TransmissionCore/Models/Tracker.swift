import Foundation

/// One tracker announce endpoint for a torrent.
public struct Tracker: Identifiable, Hashable, Sendable {
    public var id: String { "\(tier)-\(host)" }
    /// Failover tier. Lower numbers are tried first; same-tier trackers race.
    public var tier: Int
    public var host: String
    public var state: TrackerState
    /// Human-readable status line, e.g. "Working — announced 2m ago".
    public var statusMessage: String
    public var seedCount: Int
    public var leechCount: Int
    public var downloadCount: Int

    public init(
        tier: Int,
        host: String,
        state: TrackerState,
        statusMessage: String,
        seedCount: Int,
        leechCount: Int,
        downloadCount: Int
    ) {
        self.tier = tier
        self.host = host
        self.state = state
        self.statusMessage = statusMessage
        self.seedCount = seedCount
        self.leechCount = leechCount
        self.downloadCount = downloadCount
    }
}

public enum TrackerState: String, Sendable, Hashable, CaseIterable, Codable {
    case working, idle, error
}
