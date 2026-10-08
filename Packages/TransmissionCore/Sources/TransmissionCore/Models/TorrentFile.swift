import Foundation

/// One file inside a torrent's content payload.
public struct TorrentFile: Identifiable, Hashable, Sendable {
    /// File index within the torrent. Stable across polls.
    public var id: Int
    public var name: String
    public var size: Int64
    public var progress: Double
    public var priority: TorrentPriority
    public var wanted: Bool

    public init(
        id: Int,
        name: String,
        size: Int64,
        progress: Double,
        priority: TorrentPriority = .normal,
        wanted: Bool = true
    ) {
        self.id = id
        self.name = name
        self.size = size
        self.progress = progress
        self.priority = priority
        self.wanted = wanted
    }
}
