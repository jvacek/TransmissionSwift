import Foundation

/// Sidebar row identity. The store keeps a set of these so separate sections
/// can be selected together while still enforcing one selection per section.
public enum SidebarFilter: Hashable, Sendable {
    case status(TorrentStatusFilter)
    case tracker(host: String)
    case folder(name: String)
    case label(name: String)
}

extension SidebarFilter {
    public enum Group: Hashable, Sendable {
        case status, tracker, folder, label
    }

    public var group: Group {
        switch self {
        case .status: return .status
        case .tracker: return .tracker
        case .folder: return .folder
        case .label: return .label
        }
    }
}

/// Composable torrent filter state. Empty facet sets mean "match all" for that
/// facet, so selecting a tracker and a label narrows with AND semantics.
public struct TorrentFilterSelection: Hashable, Sendable {
    public var statuses: Set<TorrentStatusFilter>
    public var trackers: Set<String>
    public var folders: Set<String>
    public var labels: Set<String>

    public init(
        statuses: Set<TorrentStatusFilter> = [.all],
        trackers: Set<String> = [],
        folders: Set<String> = [],
        labels: Set<String> = []
    ) {
        self.statuses = statuses
        self.trackers = trackers
        self.folders = folders
        self.labels = labels
    }

    public init(sidebarFilters: Set<SidebarFilter>) {
        self.init()
        for filter in sidebarFilters {
            switch filter {
            case .status(let status):
                setStatus(status)
            case .tracker(let host):
                trackers = [host]
            case .folder(let name):
                folders = [name]
            case .label(let name):
                labels = [name]
            }
        }
    }

    public var hasFacetFilters: Bool {
        !trackers.isEmpty || !folders.isEmpty || !labels.isEmpty
    }

    public mutating func setStatus(_ status: TorrentStatusFilter) {
        statuses = status == .all ? [.all] : [status]
    }

    public mutating func toggleTracker(_ host: String) {
        toggle(host, in: &trackers)
    }

    public mutating func toggleFolder(_ name: String) {
        toggle(name, in: &folders)
    }

    public mutating func toggleLabel(_ name: String) {
        toggle(name, in: &labels)
    }

    public mutating func clearFacets() {
        trackers = []
        folders = []
        labels = []
    }

    public mutating func reset() {
        statuses = [.all]
        clearFacets()
    }

    public func matches(_ torrent: Torrent) -> Bool {
        matchesStatus(torrent)
            && (trackers.isEmpty || trackers.contains(torrent.primaryTracker))
            && (folders.isEmpty || folders.contains(torrent.downloadFolder))
            && (labels.isEmpty || torrent.label.map(labels.contains) == true)
    }

    private func matchesStatus(_ torrent: Torrent) -> Bool {
        statuses.isEmpty
            || statuses.contains(.all)
            || statuses.contains(where: { $0.matches(torrent) })
    }

    private func toggle(_ value: String, in values: inout Set<String>) {
        if values.contains(value) {
            values.remove(value)
        } else {
            values.insert(value)
        }
    }
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
    /// Apply the sidebar filter state to the sequence.
    public func filtered(by filter: TorrentFilterSelection) -> [Torrent] {
        self.filter(filter.matches)
    }

    /// Case-insensitive substring match against the torrent name.
    /// Empty query returns the full sequence unchanged.
    public func searched(_ query: String) -> [Torrent] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Array(self) }
        return self.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }
}

extension Torrent {
    /// Sortable key for the ETA column. nil (paused/error/queued) and .infinity
    /// (seeding forever) both sort to the bottom.
    public var etaSortKey: TimeInterval { eta ?? .infinity }
}
