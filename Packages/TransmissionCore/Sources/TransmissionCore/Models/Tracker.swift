import Foundation

/// One tracker announce endpoint for a torrent.
public struct Tracker: Identifiable, Hashable, Sendable {
    /// The announce URL identifies a tracker on the daemon, so it keys the view;
    /// two entries can share a host (http and https, say).
    public var id: String { announce.isEmpty ? "\(tier)-\(host)" : announce }
    /// Failover tier. Lower numbers are tried first; same-tier trackers race.
    public var tier: Int
    public var host: String
    /// Full announce URL. Empty only for fixtures built without one.
    public var announce: String
    public var state: TrackerState
    /// Human-readable status line, e.g. "Working — announced 2m ago".
    public var statusMessage: String
    public var seedCount: Int
    public var leechCount: Int
    public var downloadCount: Int

    public init(
        tier: Int,
        host: String,
        announce: String = "",
        state: TrackerState,
        statusMessage: String,
        seedCount: Int,
        leechCount: Int,
        downloadCount: Int
    ) {
        self.tier = tier
        self.host = host
        self.announce = announce
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
