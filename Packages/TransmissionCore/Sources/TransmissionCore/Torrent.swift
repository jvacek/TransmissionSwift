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
    // Inspector-only metadata — absent from list polls; filled by
    // `inspectorData(for:)` and merged into the live torrent for display.
    public var comment: String?
    public var creator: String?
    public var createdAt: Date?
    public var isPrivate: Bool
    public var downloadedEver: Int64
    public var uploadedEver: Int64
    public var lastActivityAt: Date?
    public var magnetLink: String?

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
        trackers: [Tracker] = [],
        comment: String? = nil,
        creator: String? = nil,
        createdAt: Date? = nil,
        isPrivate: Bool = false,
        downloadedEver: Int64 = 0,
        uploadedEver: Int64 = 0,
        lastActivityAt: Date? = nil,
        magnetLink: String? = nil
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
        self.comment = comment
        self.creator = creator
        self.createdAt = createdAt
        self.isPrivate = isPrivate
        self.downloadedEver = downloadedEver
        self.uploadedEver = uploadedEver
        self.lastActivityAt = lastActivityAt
        self.magnetLink = magnetLink
    }
}

extension Torrent {
    /// Overlay the inspector-fetched metadata onto the live list-poll torrent:
    /// transfer state stays fresh from the poll while static metadata and
    /// cumulative stats come from the richer fetch. `other` wins only where it
    /// carries data (non-nil optionals); its live counters always win since the
    /// inspector fetch is at least as recent.
    public func mergingMetadata(from other: Torrent?) -> Torrent {
        guard let other, other.id == id else { return self }
        var merged = self
        merged.comment = other.comment ?? comment
        merged.creator = other.creator ?? creator
        merged.createdAt = other.createdAt ?? createdAt
        merged.isPrivate = other.isPrivate
        merged.downloadedEver = other.downloadedEver
        merged.uploadedEver = other.uploadedEver
        merged.lastActivityAt = other.lastActivityAt ?? lastActivityAt
        merged.magnetLink = other.magnetLink ?? magnetLink
        return merged
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
