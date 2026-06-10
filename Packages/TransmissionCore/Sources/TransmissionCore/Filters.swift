import Foundation

/// What the sidebar has selected. Drives which torrents the main list shows.
public enum SidebarFilter: Hashable, Sendable {
    case status(TorrentStatusFilter)
    case tracker(host: String)
    case folder(name: String)
    case label(name: String)
}

/// The status-section rows in the sidebar. `.all` matches every torrent;
/// `.active` matches anything currently downloading or seeding.
public enum TorrentStatusFilter: String, Hashable, Sendable, CaseIterable, Codable {
    case all, downloading, seeding, active, paused, checking, queued, error
}

extension TorrentStatusFilter {
    /// True when `torrent` belongs in this status bucket.
    public func matches(_ torrent: Torrent) -> Bool {
        switch self {
        case .all: return true
        case .active: return torrent.status == .downloading || torrent.status == .seeding
        case .downloading: return torrent.status == .downloading
        case .seeding: return torrent.status == .seeding
        case .paused: return torrent.status == .paused
        case .checking: return torrent.status == .checking
        case .queued: return torrent.status == .queued
        case .error: return torrent.status == .error
        }
    }
}

/// Counts shown next to each sidebar row. Recomputed whenever the torrent
/// list changes. Cheap — linear in the number of torrents, no allocations
/// the UI side needs to care about.
public struct FilterFacets: Sendable, Hashable {
    public var statusCounts: [TorrentStatusFilter: Int]
    public var trackers: [FacetEntry]
    public var folders: [FacetEntry]
    public var labels: [FacetEntry]

    public init(torrents: [Torrent]) {
        var statuses: [TorrentStatusFilter: Int] = [:]
        for filter in TorrentStatusFilter.allCases {
            statuses[filter] = torrents.lazy.filter(filter.matches).count
        }
        self.statusCounts = statuses
        self.trackers = Self.entries(torrents.map(\.primaryTracker))
        self.folders = Self.entries(torrents.map(\.downloadFolder))
        self.labels = Self.entries(torrents.compactMap(\.label))
    }

    private static func entries(_ values: [String]) -> [FacetEntry] {
        Dictionary(grouping: values, by: { $0 })
            .map { FacetEntry(name: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                lhs.count != rhs.count ? lhs.count > rhs.count : lhs.name < rhs.name
            }
    }
}

public struct FacetEntry: Identifiable, Hashable, Sendable {
    public var name: String
    public var count: Int
    public var id: String { name }

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

extension Sequence where Element == Torrent {
    /// Apply the sidebar filter to the sequence.
    public func filtered(by filter: SidebarFilter) -> [Torrent] {
        switch filter {
        case .status(let bucket): return self.filter(bucket.matches)
        case .tracker(let host): return self.filter { $0.primaryTracker == host }
        case .folder(let name): return self.filter { $0.downloadFolder == name }
        case .label(let name): return self.filter { $0.label == name }
        }
    }

    /// Case-insensitive substring match against the torrent name.
    /// Empty query returns the full sequence unchanged.
    public func searched(_ query: String) -> [Torrent] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Array(self) }
        return self.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }
}
