import Foundation
import OSLog
import Observation
import TransmissionRPC

private let logger = Logger(subsystem: "net.jvacek.TransmissionSwift", category: "inspector")

/// Surfaced to the UI when a user-initiated action fails. Identifiable so it
/// can drive SwiftUI `.alert(item:)` directly.
public enum ActionError: Error, Identifiable, Sendable {
    case failed(message: String)
    /// The torrent was already present on the daemon. The associated value is
    /// the torrent's name, for use in the alert message.
    case torrentDuplicate(name: String)

    public var id: String { localizedDescription }

    public var localizedDescription: String {
        switch self {
        case .failed(let message): return message
        case .torrentDuplicate(let name): return "\u{201C}\(name)\u{201D} is already in your list."
        }
    }

    public var title: String {
        switch self {
        case .failed: return "Action Failed"
        case .torrentDuplicate: return "Already in List"
        }
    }
}

/// The single source of truth the UI binds to. Wraps a `TorrentService`,
/// owns selection / search / filter / inspector state, and derives the
/// sidebar facets and visible-row set.
///
/// Views read this from the environment. View models stay thin.
@MainActor
@Observable
public final class TorrentStore {
    public private(set) var torrents: [Torrent] = [] {
        didSet {
            facets = FilterFacets(torrents: torrents, downloadDirectory: downloadDirectory)
            rebuildVisibleTorrents(reloadTable: false)
        }
    }
    public private(set) var connection: ConnectionState = .connecting
    public private(set) var isAlternativeSpeedEnabled: Bool = false
    /// Non-nil when a user action failed. Cleared by the view when the alert is dismissed.
    public var lastActionError: ActionError?
    /// Free space (bytes) on the daemon's download directory. Nil until the first poll completes.
    public private(set) var freeSpace: Int64? = nil
    /// Default download directory on the daemon host. Nil until the first session-get completes.
    public private(set) var downloadDirectory: String? = nil

    /// Torrent fetched with full inspector fields for the selected torrent.
    /// Nil when no torrent is selected or before the first inspector fetch.
    /// Does NOT get wiped by the main list poll — updated only by `fetchInspectorDetail`.
    public private(set) var inspectorDetail: Torrent?

    public private(set) var selectedSidebarFilters: Set<SidebarFilter> = [.status(.all)]
    public private(set) var filterSelection = TorrentFilterSelection()
    public var selectedTorrentIDs: Set<Torrent.ID> = []
    public var searchQuery: String = "" {
        didSet {
            if searchQuery != oldValue {
                rebuildVisibleTorrents(reloadTable: true)
            }
        }
    }
    public var inspectorVisible: Bool = true
    public var inspectorTab: InspectorTab = .general

    // Add-torrent sheet
    public var showAddTorrent: Bool = false
    public var addTorrentStartInMagnetMode: Bool = false
    public var addTorrentPrefilledURL: URL? = nil

    public private(set) var facets = FilterFacets(torrents: [])
    public private(set) var visibleTorrents: [Torrent] = []
    public private(set) var listPresentationRevision = 0

    public var selectedTorrents: [Torrent] {
        torrents.filter { selectedTorrentIDs.contains($0.id) }
    }

    /// True when the backing service supports mutation actions.
    public private(set) var actionsEnabled: Bool = true

    private var service: any TorrentService
    private var streamTask: Task<Void, Never>?
    private var freeSpaceTask: Task<Void, Never>?
    private var sortOrder: [KeyPathComparator<Torrent>] = [KeyPathComparator(\.name)]

    public init(service: any TorrentService) {
        self.service = service
        self.actionsEnabled = service.supportsActions
        startStream()
    }

    /// Restart the poll stream using the current service. Called by the
    /// "Reconnect" button after a disconnection.
    public func reconnect() {
        connect(service: service)
    }

    /// Suspend polling while the app is in the background. Cancels the stream
    /// and free-space tasks without changing the connection state.
    public func pausePolling() {
        streamTask?.cancel()
        freeSpaceTask?.cancel()
    }

    /// Resume polling after returning to the foreground. Restarts the stream
    /// from scratch, which also re-fetches free space and alt-speed state.
    public func resumePolling() {
        startStream()
    }

    /// Swap the backing service and restart the poll stream. Used when the
    /// active server profile changes at runtime (first-run or server switching).
    public func connect(service: any TorrentService) {
        streamTask?.cancel()
        freeSpaceTask?.cancel()
        self.service = service
        actionsEnabled = service.supportsActions
        connection = .connecting
        freeSpace = nil
        downloadDirectory = nil
        torrents = []
        startStream()
    }

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
        rebuildVisibleTorrents(reloadTable: true)
    }

    public func setSortOrder(_ sortOrder: [KeyPathComparator<Torrent>]) {
        guard self.sortOrder != sortOrder else { return }
        self.sortOrder = sortOrder
        rebuildVisibleTorrents(reloadTable: false)
    }

    private func startStream() {
        // Capture the service now so a cancelled task can't accidentally call
        // methods on whatever service connect() installs while it's running.
        let capturedService = service
        streamTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            let stream = await capturedService.torrentsStream()
            guard !Task.isCancelled else { return }
            // freeSpace() also warms the session cache in RPCTorrentService.
            self.freeSpace = await capturedService.freeSpace()
            self.downloadDirectory = await capturedService.downloadDirectory()
            // Sync alt-speed state from the now-warm cache — avoids showing the
            // wrong turtle toggle state if alt speed was enabled before launch.
            self.isAlternativeSpeedEnabled = await capturedService.isAlternativeSpeedEnabled()
            guard !Task.isCancelled else { return }
            self.startFreeSpacePoll()
            do {
                for try await snapshot in stream {
                    self.torrents = snapshot
                    if case .connected = self.connection {
                    } else {
                        self.connection = .connected
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.connection = .disconnected(reason: error.localizedDescription)
            }
        }
    }

    private func startFreeSpacePoll() {
        freeSpaceTask?.cancel()
        let capturedService = service
        freeSpaceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let v = UserDefaults.standard.double(forKey: "freeSpaceIntervalSeconds")
                let interval = v > 0 ? v : 60.0
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                self.freeSpace = await capturedService.freeSpace()
            }
        }
    }

    private func rebuildVisibleTorrents(reloadTable: Bool) {
        visibleTorrents =
            torrents
            .filtered(by: filterSelection, relativeTo: downloadDirectory)
            .searched(searchQuery)
            .sorted(using: sortOrder)
        if reloadTable {
            listPresentationRevision += 1
        }
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

    // MARK: - Actions

    public func start(_ ids: [Torrent.ID]) async {
        do { try await service.start(ids) } catch { recordError(error) }
    }

    public func stop(_ ids: [Torrent.ID]) async {
        do { try await service.stop(ids) } catch { recordError(error) }
    }

    public func remove(_ ids: [Torrent.ID], deleteLocalData: Bool = false) async {
        do { try await service.remove(ids, deleteLocalData: deleteLocalData) } catch { recordError(error) }
        selectedTorrentIDs.subtract(ids)
    }

    public func verify(_ ids: [Torrent.ID]) async {
        do { try await service.verify(ids) } catch { recordError(error) }
    }

    public func setFilesWanted(_ id: Torrent.ID, fileIDs: [TorrentFile.ID], wanted: Bool) async {
        do { try await service.setFilesWanted(id, fileIDs: fileIDs, wanted: wanted) } catch { recordError(error) }
    }

    public func setFilePriority(
        _ id: Torrent.ID, fileIDs: [TorrentFile.ID], priority: TorrentPriority
    ) async {
        do { try await service.setFilePriority(id, fileIDs: fileIDs, priority: priority) } catch { recordError(error) }
    }

    public func setOptions(_ id: Torrent.ID, options: TorrentOptions) async {
        do { try await service.setOptions(id, options: options) } catch { recordError(error) }
    }

    public func toggleAlternativeSpeed() async {
        let newValue = !isAlternativeSpeedEnabled
        do {
            try await service.setAlternativeSpeedEnabled(newValue)
            isAlternativeSpeedEnabled = newValue
        } catch {
            recordError(error)
        }
    }

    public func openAddSheet(magnetMode: Bool = false, prefilledURL: URL? = nil) {
        addTorrentStartInMagnetMode = magnetMode
        addTorrentPrefilledURL = prefilledURL
        showAddTorrent = true
    }

    public func add(
        fileURL: URL?,
        magnetURL: String?,
        destination: String,
        label: String?,
        priority: TorrentPriority,
        startWhenAdded: Bool
    ) async {
        do {
            try await service.add(
                fileURL: fileURL,
                magnetURL: magnetURL,
                destination: destination,
                label: label,
                priority: priority,
                startWhenAdded: startWhenAdded
            )
        } catch {
            recordError(error)
        }
    }

    /// Fetch inspector-level detail (files, peers, trackerStats) for a single
    /// torrent and store it in `inspectorDetail`. Clears stale detail first if
    /// the ID changed. Silently swallows errors — the tabs fall back to showing
    /// empty arrays if the fetch fails.
    public func fetchInspectorDetail(for id: Torrent.ID) async {
        if inspectorDetail?.id != id {
            inspectorDetail = nil
        }
        do {
            let detail = try await service.inspectorData(for: id)
            logger.debug(
                "Inspector fetch succeeded for id \(id): \(detail.files.count) files, \(detail.peers.count) peers, \(detail.trackers.count) trackers"
            )
            inspectorDetail = detail
        } catch {
            logger.error("Inspector fetch failed for id \(id): \(error)")
        }
    }

    public func refreshFreeSpace() async {
        freeSpace = await service.freeSpace()
    }

    public func setConnectionFailed(reason: String) {
        connection = .disconnected(reason: reason)
    }

    /// Cancel any in-flight stream and mark the connection as waiting for
    /// keychain access. Called before the blocking macOS keychain dialog so
    /// the existing mock stream can't race back and overwrite the state.
    public func beginKeychainWait() {
        streamTask?.cancel()
        freeSpaceTask?.cancel()
        connection = .awaitingKeychain
        torrents = []
        freeSpace = nil
    }

    /// Override the connection state — used by the debug menu (slice 6).
    public func simulateConnection(_ state: ConnectionState) {
        connection = state
    }

    // MARK: - Private helpers

    private func recordError(_ error: any Error) {
        if case .torrentDuplicate(let name) = error as? TransmissionError {
            lastActionError = .torrentDuplicate(name: name)
        } else {
            lastActionError = .failed(message: error.localizedDescription)
        }
    }
}
