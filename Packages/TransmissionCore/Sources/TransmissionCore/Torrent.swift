import Foundation

/// One torrent as the UI thinks about it. The wire-protocol equivalent is the
/// subset of `torrent-get` fields we request — see `RPCTorrentService` (later).
public struct Torrent: Identifiable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var hash: String
    public var size: Int64
    public var status: TorrentStatus
    public var progress: Double
    public var downloadSpeed: Int64
    public var uploadSpeed: Int64
    public var connectedPeerCount: Int
    public var availablePeerCount: Int
    public var seedCount: Int
    /// nil = unknown (paused, error, queued). `.infinity` = idle (seeding forever).
    public var eta: TimeInterval?
    public var ratio: Double
    public var primaryTracker: String
    public var downloadFolder: String
    public var addedAt: Date
    /// Tags assigned to the torrent. Empty = untagged. Transmission supports
    /// multiple labels per torrent (array on the wire); the daemon replaces the
    /// whole set on write.
    public var labels: [String]
    public var priority: TorrentPriority
    public var pieces: Int
    public var pieceSize: Int64
    public var havePieces: Int
    public var queuePosition: Int?
    public var errorMessage: String?
    public var options: TorrentOptions
    public var files: [TorrentFile]
    public var peers: [Peer]
    public var trackers: [Tracker]

    public init(
        id: Int,
        name: String,
        hash: String,
        size: Int64,
        status: TorrentStatus,
        progress: Double,
        downloadSpeed: Int64 = 0,
        uploadSpeed: Int64 = 0,
        connectedPeerCount: Int = 0,
        availablePeerCount: Int = 0,
        seedCount: Int = 0,
        eta: TimeInterval? = nil,
        ratio: Double = 0,
        primaryTracker: String,
        downloadFolder: String,
        addedAt: Date,
        labels: [String] = [],
        priority: TorrentPriority = .normal,
        pieces: Int,
        pieceSize: Int64,
        havePieces: Int,
        queuePosition: Int? = nil,
        errorMessage: String? = nil,
        options: TorrentOptions = TorrentOptions(),
        files: [TorrentFile] = [],
        peers: [Peer] = [],
        trackers: [Tracker] = []
    ) {
        self.id = id
        self.name = name
        self.hash = hash
        self.size = size
        self.status = status
        self.progress = progress
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.connectedPeerCount = connectedPeerCount
        self.availablePeerCount = availablePeerCount
        self.seedCount = seedCount
        self.eta = eta
        self.ratio = ratio
        self.primaryTracker = primaryTracker
        self.downloadFolder = downloadFolder
        self.addedAt = addedAt
        self.labels = labels
        self.priority = priority
        self.pieces = pieces
        self.pieceSize = pieceSize
        self.havePieces = havePieces
        self.queuePosition = queuePosition
        self.errorMessage = errorMessage
        self.options = options
        self.files = files
        self.peers = peers
        self.trackers = trackers
    }
}

public enum TorrentStatus: String, Sendable, Hashable, CaseIterable, Codable {
    case downloading, seeding, paused, checking, queued, error, completed
}

/// Case order is the canonical display order for menus and dropdowns — high
/// always on top. Sorting (table column) uses the raw string, not this order.
public enum TorrentPriority: String, Sendable, Hashable, CaseIterable, Codable {
    case high, normal, low
}
