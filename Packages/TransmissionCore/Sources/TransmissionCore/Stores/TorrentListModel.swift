import Foundation
import Observation

/// The torrent list and everything derived from it: the rows themselves, the
/// sidebar facets, the filtered/searched/sorted visible set, selection, search,
/// filter and sort state, and the persisted sort preference.
///
/// Pure list logic — it never touches the service or the connection. The
/// coordinator (`TorrentStore`) feeds it snapshots via `setTorrents(_:)` and
/// the daemon's download directory via `setDownloadDirectory(_:)`.
@MainActor
@Observable
public final class TorrentListModel {
    public private(set) var torrents: [Torrent] = []
    public private(set) var facets = FilterFacets(torrents: [])
    public private(set) var visibleTorrents: [Torrent] = []
    /// Default download directory on the daemon host; drives folder-relative
    /// filtering and facet grouping. Nil until the first session-get completes.
    public private(set) var downloadDirectory: String? = nil

    public private(set) var selectedSidebarFilters: Set<SidebarFilter> = [.status(.all)]
    public private(set) var filterSelection = TorrentFilterSelection()
    public var selectedTorrentIDs: Set<Torrent.ID> = []
    public var searchQuery: String = "" {
        didSet {
            if searchQuery != oldValue {
                rebuildVisibleTorrents()
            }
        }
    }

    /// Facet-relevant projection of the last torrent set (status, tracker,
    /// folder, label). Recomputing `FilterFacets` is only needed when one of
    /// these changes — a poll that only moved speeds skips the grouping work.
    private var facetSignature: [FacetSignature] = []
    private struct FacetSignature: Equatable {
        let status: TorrentStatus
        let primaryTracker: String
        let downloadFolder: String
        let labels: [String]
    }

    /// Where the sort preference lives. Injected so the model can be tested
    /// without the shared `UserDefaults`.
    private let preferences: any TablePreferencesStoring

    public init(preferences: any TablePreferencesStoring = UserDefaultsTablePreferencesStore()) {
        self.preferences = preferences
    }

    public var selectedTorrents: [Torrent] {
        torrents.filter { selectedTorrentIDs.contains($0.id) }
    }

    // MARK: - Sort preference

    public var tablePreferences: TablePreferences {
        get { preferences.tablePreferences }
        set { preferences.tablePreferences = newValue }
    }

    // MARK: - Snapshots

    /// Replace the torrent snapshot and run the full cascade: prune selections
    /// pointing at torrents the daemon no longer has, recompute facets when a
    /// facet-relevant field changed, drop sidebar filters whose facet vanished,
    /// then rebuild the visible rows.
    public func setTorrents(_ torrents: [Torrent]) {
        self.torrents = torrents
        // Prune selections pointing at torrents the daemon no longer has
        // (removed externally). Skip the empty transition set so a
        // reconnect/connect doesn't wipe the selection.
        if !torrents.isEmpty {
            let liveIDs = Set(torrents.map(\.id))
            if !selectedTorrentIDs.isSubset(of: liveIDs) {
                selectedTorrentIDs.formIntersection(liveIDs)
            }
        }
        rebuildFacetsIfChanged()
        pruneSidebarFiltersIfNeeded()
        rebuildVisibleTorrents()
    }

    /// Set the daemon's default download directory. Forces a facet recompute
    /// because folder grouping/relativity depends on it, even though the
    /// facet-relevant signature doesn't change.
    public func setDownloadDirectory(_ directory: String?) {
        guard downloadDirectory != directory else { return }
        downloadDirectory = directory
        facetSignature = []
        rebuildFacetsIfChanged()
        rebuildVisibleTorrents()
    }

    // MARK: - Filters

    public func setStatusFilter(_ status: TorrentStatusFilter) {
        if status != .all, selectedSidebarFilters.contains(.status(status)) {
            setSidebarFilter(.status(.all))
        } else {
            setSidebarFilter(.status(status))
        }
    }

    public func toggleTrackerFilter(_ host: String) {
        toggleSidebarFilter(.tracker(host: host))
    }

    public func toggleFolderFilter(_ name: String) {
        toggleSidebarFilter(.folder(name: name))
    }

    public func toggleLabelFilter(_ name: String) {
        toggleSidebarFilter(.label(name: name))
    }

    public func resetFilters() {
        setSidebarFilters([.status(.all)])
    }

    public func setSidebarFilter(_ filter: SidebarFilter) {
        setSidebarFilters(normalizedSidebarFilters(selectedSidebarFilters.union([filter]), preferred: filter))
    }

    public func toggleSidebarFilter(_ filter: SidebarFilter) {
        if selectedSidebarFilters.contains(filter), filter.group != .status {
            setSidebarFilters(selectedSidebarFilters.subtracting([filter]))
        } else {
            setSidebarFilter(filter)
        }
    }

    public func setSidebarFilters(_ filters: Set<SidebarFilter>) {
        let next = normalizedSidebarFilters(filters)
        guard next != selectedSidebarFilters else { return }
        selectedSidebarFilters = next
        filterSelection = TorrentFilterSelection(sidebarFilters: next)
        rebuildVisibleTorrents()
    }

    /// Sets and persists the sort in one step. The persisted `tablePreferences`
    /// is the single source of truth — there is no parallel in-memory sort
    /// state to drift from it.
    public func setSortOrder(column: TableColumn, ascending: Bool) {
        let current = tablePreferences
        guard current.sortColumn != column.rawValue || current.sortAscending != ascending else {
            return
        }
        tablePreferences = TablePreferences(sortColumn: column.rawValue, sortAscending: ascending)
        rebuildVisibleTorrents()
    }

    // MARK: - Derivation

    private func rebuildVisibleTorrents() {
        // Runs on every snapshot: sort keys (speeds, progress, ETA) move each
        // poll, so unlike the facets this cannot be gated by a signature. The
        // table's `TorrentTableRowStore` guard keeps it from repainting.
        // The persisted preference is the single sort source; read it once per
        // rebuild rather than caching a second copy that can drift.
        let prefs = tablePreferences
        let column = TableColumn(rawValue: prefs.sortColumn) ?? .name
        visibleTorrents =
            torrents
            .filtered(by: filterSelection, relativeTo: downloadDirectory)
            .searched(searchQuery)
            .sorted(using: column.comparator(order: prefs.sortAscending ? .forward : .reverse))
    }

    /// Recomputes `facets` only when the fields the sidebar reads from actually
    /// changed, instead of every poll tick.
    private func rebuildFacetsIfChanged() {
        let signature = torrents.map { torrent in
            FacetSignature(
                status: torrent.status,
                primaryTracker: torrent.primaryTracker,
                downloadFolder: torrent.downloadFolder,
                labels: torrent.labels)
        }
        guard signature != facetSignature else { return }
        facetSignature = signature
        facets = FilterFacets(torrents: torrents, downloadDirectory: downloadDirectory)
    }

    /// Drop sidebar filters that reference label / folder / tracker facets that
    /// no longer exist (their last torrent was removed or relabelled). Without
    /// this, deleting the last tagged torrent leaves its label filter applied —
    /// and since the whole Labels section disappears, there's no way to clear
    /// it. Status filters are always valid. Skipped while the set is empty so a
    /// transient empty snapshot (reconnect) doesn't wipe the filters.
    private func pruneSidebarFiltersIfNeeded() {
        guard !torrents.isEmpty else { return }
        let labelNames = Set(facets.labels.map(\.name))
        let folderNames = Set(facets.folders.map(\.name))
        let trackerHosts = Set(facets.trackers.map(\.name))
        let labelsSectionVisible = !labelNames.isEmpty

        let pruned = selectedSidebarFilters.filter { filter in
            switch filter {
            case .status: return true
            case .tracker(let host): return trackerHosts.contains(host)
            case .folder(let name): return folderNames.contains(name)
            case .label(let name):
                // "No label" only exists while the section is visible.
                if name == LabelFilter.noLabelName { return labelsSectionVisible }
                return labelNames.contains(name)
            }
        }
        guard pruned != selectedSidebarFilters else { return }
        selectedSidebarFilters = pruned
        filterSelection = TorrentFilterSelection(sidebarFilters: pruned)
    }

    private func normalizedSidebarFilters(
        _ filters: Set<SidebarFilter>,
        preferred: SidebarFilter? = nil
    ) -> Set<SidebarFilter> {
        var byGroup: [SidebarFilter.Group: SidebarFilter] = [:]
        for filter in filters {
            byGroup[filter.group] = filter
        }
        if let preferred {
            byGroup[preferred.group] = preferred
        }
        if byGroup[.status] == nil {
            byGroup[.status] = .status(.all)
        }
        return Set(byGroup.values)
    }
}
