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

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .name: return "Name"
        case .size: return "Size"
        case .progress: return "Progress"
        case .downloadSpeed: return "↓ Speed"
        case .uploadSpeed: return "↑ Speed"
        case .eta: return "ETA"
        case .ratio: return "Ratio"
        case .addedAt: return "Added"
        case .primaryTracker: return "Tracker"
        case .connectedPeers: return "Peers"
        case .availablePeers: return "Available"
        case .seeds: return "Seeds"
        case .queuePosition: return "Queue"
        case .label: return "Label"
        case .priority: return "Priority"
        case .status: return "Status"
        case .errorMessage: return "Error"
        case .pieces: return "Pieces"
        case .downloadFolder: return "Folder"
        case .hash: return "Hash"
        }
    }

    public var defaultVisible: Bool {
        switch self {
        case .name, .size, .progress, .downloadSpeed, .uploadSpeed, .eta, .addedAt, .primaryTracker:
            return true
        default:
            return false
        }
    }

    public var defaultWidth: Double? {
        switch self {
        case .name: return 400
        case .size: return 74
        case .progress: return 130
        case .downloadSpeed: return 78
        case .uploadSpeed: return 78
        case .eta: return 66
        case .ratio: return 60
        case .addedAt: return 100
        case .primaryTracker: return 120
        case .connectedPeers: return 60
        case .availablePeers: return 60
        case .seeds: return 60
        case .queuePosition: return 60
        case .label: return 100
        case .priority: return 80
        case .status: return 100
        case .errorMessage: return 150
        case .pieces: return 80
        case .downloadFolder: return 180
        case .hash: return 160
        }
    }

    public var minWidth: Double {
        switch self {
        case .name: return 240
        case .size: return 54
        case .progress: return 80
        case .downloadSpeed: return 60
        case .uploadSpeed: return 60
        case .eta: return 52
        case .ratio: return 50
        case .addedAt: return 72
        case .primaryTracker: return 80
        case .connectedPeers: return 50
        case .availablePeers: return 50
        case .seeds: return 50
        case .queuePosition: return 50
        case .label: return 80
        case .priority: return 60
        case .status: return 80
        case .errorMessage: return 100
        case .pieces: return 60
        case .downloadFolder: return 120
        case .hash: return 120
        }
    }

    public var maxWidth: Double {
        switch self {
        case .name: return 600
        case .size: return 120
        case .progress: return 200
        case .downloadSpeed: return 120
        case .uploadSpeed: return 120
        case .eta: return 100
        case .ratio: return 80
        case .addedAt: return 140
        case .primaryTracker: return 200
        case .connectedPeers: return 80
        case .availablePeers: return 80
        case .seeds: return 80
        case .queuePosition: return 80
        case .label: return 150
        case .priority: return 100
        case .status: return 140
        case .errorMessage: return 250
        case .pieces: return 100
        case .downloadFolder: return 300
        case .hash: return 240
        }
    }
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
