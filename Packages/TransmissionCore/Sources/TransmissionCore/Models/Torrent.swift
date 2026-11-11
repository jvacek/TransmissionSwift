import Foundation

/// One torrent as the UI thinks about it. The wire-protocol equivalent is the
/// subset of `torrent-get` fields we request — see `RPCTorrentService` (later).
public struct Torrent: Identifiable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var hash: String
    public var size: Int64
    public var status: TorrentStatus
    /// The daemon's wire status was 0. Not derivable from `status`, which
    /// reports every finished torrent as `.completed` whether it is stopped or
    /// still seeding.
    public var isStopped: Bool
    public var progress: Double
    public var downloadSpeed: Int64
    public var uploadSpeed: Int64
    public var connectedPeerCount: Int
    /// Peers currently sending to us (active download links) and receiving from
    /// us (active upload links), plus webseeds sending to us. Back `isActive`.
    public var peersSendingToUs: Int
    public var peersGettingFromUs: Int
    public var webseedsSendingToUs: Int
    public var availablePeerCount: Int
    public var seedCount: Int
    /// nil = unknown (paused, error, queued). `.infinity` = idle (seeding forever).
    public var eta: TimeInterval?
    /// Upload/download ratio, always >= 0. 0 means "not available yet" (nothing
    /// downloaded); the UI renders it as an em dash.
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
    /// Daemon timestamps, mapped from `doneDate` / `startDate`. nil = not yet
    /// (incomplete / never started); the UI renders an em dash.
    public var completedAt: Date?
    public var startedAt: Date?
    /// Lifetime counters in seconds, from `secondsDownloading` / `secondsSeeding`.
    public var secondsDownloading: Int64
    public var secondsSeeding: Int64
    /// Bytes still missing (`leftUntilDone`) and total wanted size
    /// (`sizeWhenDone`); 0 remaining means complete.
    public var leftUntilDone: Int64
    public var sizeWhenDone: Int64
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
        isStopped: Bool = false,
        progress: Double,
        downloadSpeed: Int64 = 0,
        uploadSpeed: Int64 = 0,
        connectedPeerCount: Int = 0,
        peersSendingToUs: Int = 0,
        peersGettingFromUs: Int = 0,
        webseedsSendingToUs: Int = 0,
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
        completedAt: Date? = nil,
        startedAt: Date? = nil,
        secondsDownloading: Int64 = 0,
        secondsSeeding: Int64 = 0,
        leftUntilDone: Int64 = 0,
        sizeWhenDone: Int64 = 0,
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
        self.isStopped = isStopped
        self.progress = progress
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.connectedPeerCount = connectedPeerCount
        self.peersSendingToUs = peersSendingToUs
        self.peersGettingFromUs = peersGettingFromUs
        self.webseedsSendingToUs = webseedsSendingToUs
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
        self.completedAt = completedAt
        self.startedAt = startedAt
        self.secondsDownloading = secondsDownloading
        self.secondsSeeding = secondsSeeding
        self.leftUntilDone = leftUntilDone
        self.sizeWhenDone = sizeWhenDone
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
    /// True when at least one live transfer link exists — a peer or webseed
    /// moving data in either direction — or the torrent is verifying. Mirrors
    /// Transmission's web (`testState(FilterActive)`) and GTK
    /// (`Activity::ACTIVE`) definitions: an idle seed or a stalled download is
    /// not active.
    public var isActive: Bool {
        status == .checking
            || peersSendingToUs > 0
            || peersGettingFromUs > 0
            || webseedsSendingToUs > 0
    }

    /// A magnet link assembled from the list poll's fields. `magnetLink` arrives
    /// only with the inspector fetch, so list-level actions can't use it.
    public var magnetURI: String {
        var parts = ["xt=urn:btih:\(hash.lowercased())"]
        if let name = name.addingPercentEncoding(withAllowedCharacters: Self.magnetValueAllowed),
            !name.isEmpty
        {
            parts.append("dn=\(name)")
        }
        for tracker in trackers where !tracker.announce.isEmpty {
            guard
                let announce = tracker.announce.addingPercentEncoding(
                    withAllowedCharacters: Self.magnetValueAllowed)
            else { continue }
            parts.append("tr=\(announce)")
        }
        return "magnet:?" + parts.joined(separator: "&")
    }

    /// `urlQueryAllowed` minus the characters that would split one query value
    /// into two.
    private static let magnetValueAllowed: CharacterSet = CharacterSet.urlQueryAllowed
        .subtracting(CharacterSet(charactersIn: "&=+?#"))

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
