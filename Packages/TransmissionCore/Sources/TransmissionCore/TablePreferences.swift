import Foundation

public enum TableColumn: String, CaseIterable, Identifiable, Hashable, Sendable, Codable {
    case name
    case size
    case progress
    case downloadSpeed
    case uploadSpeed
    case eta
    case ratio
    case addedAt
    case completedAt
    case startedAt
    case lastActivityAt
    case primaryTracker
    case connectedPeers
    case availablePeers
    case seeds
    case queuePosition
    case label
    case priority
    case status
    case errorMessage
    case pieces
    case downloadFolder
    case hash
    case downloadedEver
    case uploadedEver
    case leftUntilDone
    case sizeWhenDone
    case secondsDownloading
    case secondsSeeding
    case downloadLimit
    case uploadLimit
    case seedRatioLimit
    case seedIdleLimit
    case peerLimit

    public var id: String { rawValue }

    // Presentation specs (titles, widths, default visibility) live in the app
    // target's `TorrentTableColumns` — the single source of truth for the table.
}

extension TableColumn {
    public func comparator(order: SortOrder) -> KeyPathComparator<Torrent> {
        switch self {
        case .name: return KeyPathComparator(\Torrent.name, order: order)
        case .size: return KeyPathComparator(\Torrent.size, order: order)
        case .progress: return KeyPathComparator(\Torrent.progress, order: order)
        case .downloadSpeed: return KeyPathComparator(\Torrent.downloadSpeed, order: order)
        case .uploadSpeed: return KeyPathComparator(\Torrent.uploadSpeed, order: order)
        case .eta: return KeyPathComparator(\Torrent.etaSortKey, order: order)
        case .ratio: return KeyPathComparator(\Torrent.ratio, order: order)
        case .addedAt: return KeyPathComparator(\Torrent.addedAt, order: order)
        case .completedAt: return KeyPathComparator(\Torrent.completedAtSortKey, order: order)
        case .startedAt: return KeyPathComparator(\Torrent.startedAtSortKey, order: order)
        case .lastActivityAt: return KeyPathComparator(\Torrent.lastActivityAtSortKey, order: order)
        case .primaryTracker: return KeyPathComparator(\Torrent.primaryTracker, order: order)
        case .connectedPeers: return KeyPathComparator(\Torrent.connectedPeerCount, order: order)
        case .availablePeers: return KeyPathComparator(\Torrent.availablePeerCount, order: order)
        case .seeds: return KeyPathComparator(\Torrent.seedCount, order: order)
        case .queuePosition: return KeyPathComparator(\Torrent.queuePositionSortKey, order: order)
        case .label: return KeyPathComparator(\Torrent.labelSortKey, order: order)
        case .priority: return KeyPathComparator(\Torrent.priority.rawValue, order: order)
        case .status: return KeyPathComparator(\Torrent.status.rawValue, order: order)
        case .errorMessage: return KeyPathComparator(\Torrent.errorMessageSortKey, order: order)
        case .pieces: return KeyPathComparator(\Torrent.havePieces, order: order)
        case .downloadFolder: return KeyPathComparator(\Torrent.downloadFolder, order: order)
        case .hash: return KeyPathComparator(\Torrent.hash, order: order)
        case .downloadedEver: return KeyPathComparator(\Torrent.downloadedEver, order: order)
        case .uploadedEver: return KeyPathComparator(\Torrent.uploadedEver, order: order)
        case .leftUntilDone: return KeyPathComparator(\Torrent.leftUntilDone, order: order)
        case .sizeWhenDone: return KeyPathComparator(\Torrent.sizeWhenDone, order: order)
        case .secondsDownloading: return KeyPathComparator(\Torrent.secondsDownloading, order: order)
        case .secondsSeeding: return KeyPathComparator(\Torrent.secondsSeeding, order: order)
        case .downloadLimit: return KeyPathComparator(\Torrent.downloadLimitSortKey, order: order)
        case .uploadLimit: return KeyPathComparator(\Torrent.uploadLimitSortKey, order: order)
        case .seedRatioLimit: return KeyPathComparator(\Torrent.seedRatioLimitSortKey, order: order)
        case .seedIdleLimit: return KeyPathComparator(\Torrent.seedIdleLimitSortKey, order: order)
        case .peerLimit: return KeyPathComparator(\Torrent.options.peerLimit, order: order)
        }
    }
}

public struct TablePreferences: Codable, Sendable {
    public var sortColumn: String
    public var sortAscending: Bool

    public init(
        sortColumn: String = "name",
        sortAscending: Bool = true
    ) {
        self.sortColumn = sortColumn
        self.sortAscending = sortAscending
    }
}
