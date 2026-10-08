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

/// A removal awaiting user confirmation. Identifiable so it can drive
/// SwiftUI `.confirmationDialog(item:)` directly.
public struct PendingRemoval: Identifiable, Sendable {
    public let id = UUID()
    public let ids: [Torrent.ID]
    public let deleteLocalData: Bool
}

/// The single source of truth the UI binds to. Wraps a read-only
/// `TorrentReading` (plus an optional `TorrentMutating`), owns the connection
/// state machine and the poll loop, and coordinates the focused collaborator
/// models.
///
/// Views read this from the environment and reach the collaborators through it
/// (e.g. `store.list.visibleTorrents`).
@MainActor
@Observable
public final class TorrentStore {
    /// The torrent list and everything derived from it: rows, facets,
    /// selection, search, filters, sort.
    public let list = TorrentListModel()

    public private(set) var connection: ConnectionState = .connecting
    public private(set) var isAlternativeSpeedEnabled: Bool = false
    /// Session-level settings (speed limits, network, queue, seed ratio/idle)
    /// for the connected daemon. Nil until the first session-poll completes, or
    /// when disconnected. Not the same shape as `@AppStorage` — these are the
    /// daemon's values, so the Speed/Network panes bind here rather than to
    /// UserDefaults.
    public private(set) var sessionSettings: SessionSettings? = nil
    /// Result of the last `port-test`: nil means "not tested / unknown", true
    /// means the peer port is reachable, false means it is not.
    public private(set) var portIsOpen: Bool? = nil
    /// Non-nil when a user action failed. Cleared by the view when the alert is dismissed.
    public var lastActionError: ActionError?
    /// Free space (bytes) on the daemon's download directory. Nil until the first poll completes.
    public private(set) var freeSpace: Int64? = nil
    /// The daemon's long version string (e.g. `"4.1.2 (f234716f3e)"`). Nil until
    /// the first session-poll completes, or when disconnected. Pre-fills the
    /// bug-report template.
    public private(set) var daemonVersion: String? = nil
    /// Current + lifetime transfer statistics (`session-stats`). Fetched on
    /// demand when the status-bar stats popover opens; nil until then.
    public private(set) var sessionStats: SessionStats? = nil

    /// Torrent fetched with full inspector fields for the selected torrent.
    /// Nil when no torrent is selected or before the first inspector fetch.
    /// Does NOT get wiped by the main list poll — updated only by `fetchInspectorDetail`.
    public private(set) var inspectorDetail: Torrent?
    public var inspectorVisible: Bool = true {
        didSet {
            if oldValue != inspectorVisible {
                UserDefaults.standard.set(inspectorVisible, forKey: PreferenceKeys.inspectorVisible)
            }
        }
    }
    public var inspectorTab: InspectorTab = .general

    // Add-torrent sheet
    public var showAddTorrent: Bool = false
    public var addTorrentStartInMagnetMode: Bool = false
    public var addTorrentPrefilledURL: URL? = nil

    // Edit-labels popup
    public var showEditLabels: Bool = false
    public var editLabelsTargetIDs: [Torrent.ID] = []

    // Set-location popup
    public var showSetLocation: Bool = false
    public var setLocationTargetIDs: [Torrent.ID] = []

    // Rename-torrent popup (single-torrent only — `torrent-rename-path`
    // requires exactly one id)
    public var showRenameTorrent: Bool = false
    public var renameTorrentTargetID: Torrent.ID?

    // Remove confirmation
    public var pendingRemoval: PendingRemoval? = nil

    /// True while the app has a live connection to a daemon. Gates any
    /// session-side setting that can only be read/changed when connected.
    public var isConnected: Bool {
        connection.isConnected
    }

    /// True when the backing service supports mutation actions.
    public private(set) var actionsEnabled: Bool = true

    /// Whether the connected daemon supports labels (rpc-version >= 17). Gates
    /// the "Edit Labels" affordances; refreshed whenever the session is polled.
    public private(set) var supportsLabels: Bool = true

    private var service: any TorrentReading
    /// The mutation half of the service, when it has one. Nil for read-only
    /// sources (snapshot replay), which disables every action.
    private var mutations: (any TorrentMutating)?
    private var streamTask: Task<Void, Never>?
    private var freeSpaceTask: Task<Void, Never>?

    public init(service: any TorrentReading) {
        self.service = service
        self.mutations = service as? any TorrentMutating
        self.actionsEnabled = self.mutations != nil
        if UserDefaults.standard.object(forKey: PreferenceKeys.inspectorVisible) != nil {
            self.inspectorVisible = UserDefaults.standard.bool(forKey: PreferenceKeys.inspectorVisible)
        }
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
    public func connect(service: any TorrentReading) {
        streamTask?.cancel()
        freeSpaceTask?.cancel()
        self.service = service
        mutations = service as? any TorrentMutating
        actionsEnabled = mutations != nil
        connection = .connecting
        freeSpace = nil
        daemonVersion = nil
        list.setDownloadDirectory(nil)
        sessionSettings = nil
        supportsLabels = true
        list.setTorrents([])
        // Sidebar filters are per-server state — a tracker/folder/label filter
        // from server A would otherwise show "0 torrents" against server B's
        // (different) tracker set until the user re-picks one.
        list.resetFilters()
        startStream()
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
            self.daemonVersion = await capturedService.daemonVersion()
            self.list.setDownloadDirectory(await capturedService.downloadDirectory())
            // Sync alt-speed state from the now-warm cache — avoids showing the
            // wrong turtle toggle state if alt speed was enabled before launch.
            self.isAlternativeSpeedEnabled = await capturedService.isAlternativeSpeedEnabled()
            self.supportsLabels = await capturedService.supportsLabels()
            self.sessionSettings = await capturedService.sessionSettings()
            guard !Task.isCancelled else { return }
            self.startFreeSpacePoll()
            do {
                for try await snapshot in stream {
                    self.list.setTorrents(snapshot)
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
                let v = UserDefaults.standard.double(forKey: PreferenceKeys.freeSpaceIntervalSeconds)
                let interval = v > 0 ? v : 60.0
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                self.freeSpace = await capturedService.freeSpace()
                self.daemonVersion = await capturedService.daemonVersion()
                self.supportsLabels = await capturedService.supportsLabels()
                self.sessionSettings = await capturedService.sessionSettings()
            }
        }
    }

    // MARK: - Actions

    public func start(_ ids: [Torrent.ID]) async {
        guard let mutations else { return }
        do { try await mutations.start(ids) } catch { recordError(error) }
    }

    public func stop(_ ids: [Torrent.ID]) async {
        guard let mutations else { return }
        do { try await mutations.stop(ids) } catch { recordError(error) }
    }

    public func remove(_ ids: [Torrent.ID], deleteLocalData: Bool = false) async {
        guard let mutations else { return }
        do { try await mutations.remove(ids, deleteLocalData: deleteLocalData) } catch { recordError(error) }
        list.selectedTorrentIDs.subtract(ids)
    }

    /// Request a removal, honouring the "Confirm before removing" app pref.
    /// With confirmation on, stages a `PendingRemoval` for the view to confirm;
    /// with it off, removes immediately. No-ops when nothing is selected.
    /// `confirm` defaults to the app pref so tests can inject it directly
    /// (parallel tests can't safely share `UserDefaults`).
    public func requestRemove(
        _ ids: [Torrent.ID], deleteLocalData: Bool = false,
        confirm: Bool = UserDefaults.standard.bool(forKey: PreferenceKeys.confirmRemove)
    ) {
        guard actionsEnabled, !ids.isEmpty else { return }
        if confirm {
            pendingRemoval = PendingRemoval(ids: ids, deleteLocalData: deleteLocalData)
        } else {
            Task { await remove(ids, deleteLocalData: deleteLocalData) }
        }
    }

    public func confirmPendingRemoval() {
        guard let pending = pendingRemoval else { return }
        pendingRemoval = nil
        Task { await remove(pending.ids, deleteLocalData: pending.deleteLocalData) }
    }

    public func cancelPendingRemoval() {
        pendingRemoval = nil
    }

    public func verify(_ ids: [Torrent.ID]) async {
        guard let mutations else { return }
        do { try await mutations.verify(ids) } catch { recordError(error) }
    }

    public func reannounce(_ ids: [Torrent.ID]) async {
        guard let mutations else { return }
        do { try await mutations.reannounce(ids) } catch { recordError(error) }
    }

    public func setFilesWanted(_ id: Torrent.ID, fileIDs: [TorrentFile.ID], wanted: Bool) async {
        guard let mutations else { return }
        do {
            try await mutations.setFilesWanted(id, fileIDs: fileIDs, wanted: wanted)
            await refreshInspectorIfCurrent(id)
        } catch { recordError(error) }
    }

    public func setFilePriority(
        _ id: Torrent.ID, fileIDs: [TorrentFile.ID], priority: TorrentPriority
    ) async {
        guard let mutations else { return }
        do {
            try await mutations.setFilePriority(id, fileIDs: fileIDs, priority: priority)
            await refreshInspectorIfCurrent(id)
        } catch { recordError(error) }
    }

    public func setPriority(_ ids: [Torrent.ID], priority: TorrentPriority) async {
        guard let mutations else { return }
        do { try await mutations.setPriority(ids, priority: priority) } catch { recordError(error) }
    }

    public func setOptions(_ id: Torrent.ID, options: TorrentOptions) async {
        guard let mutations else { return }
        do { try await mutations.setOptions(id, options: options) } catch { recordError(error) }
    }

    public func toggleAlternativeSpeed() async {
        guard let mutations else { return }
        let newValue = !isAlternativeSpeedEnabled
        do {
            try await mutations.setAlternativeSpeedEnabled(newValue)
            isAlternativeSpeedEnabled = newValue
            sessionSettings?.altSpeedEnabled = newValue
        } catch {
            recordError(error)
        }
    }

    /// Apply a session-side setting change. `mutate` mutates a copy of the
    /// current `SessionSettings`; the store diffs it to build a patch (only the
    /// changed fields are sent), applies it optimistically, and rolls back /
    /// re-reads on failure. Requires a live session; no-ops otherwise.
    public func updateSessionSettings(_ mutate: (inout SessionSettings) -> Void) async {
        guard let mutations, var current = sessionSettings else { return }
        let before = current
        mutate(&current)
        guard current != before else { return }
        let patch = SessionSettingsPatch(before: before, updated: current)
        sessionSettings = current
        isAlternativeSpeedEnabled = current.altSpeedEnabled
        do {
            try await mutations.applySessionSettings(patch)
            sessionSettings = await service.sessionSettings() ?? current
            isAlternativeSpeedEnabled = sessionSettings?.altSpeedEnabled ?? current.altSpeedEnabled
        } catch {
            recordError(error)
            sessionSettings = await service.sessionSettings() ?? before
            isAlternativeSpeedEnabled = sessionSettings?.altSpeedEnabled ?? before.altSpeedEnabled
        }
    }

    /// Ask the daemon whether its peer port is reachable from the outside
    /// (`port-test`). No-ops when disconnected or the service can't answer.
    public func testPort() async {
        guard isConnected else { return }
        guard let result = await service.isPortOpen() else {
            lastActionError = .failed(message: "The connected server couldn't report its port status.")
            return
        }
        portIsOpen = result
    }

    public func openAddSheet(magnetMode: Bool = false, prefilledURL: URL? = nil) {
        addTorrentStartInMagnetMode = magnetMode
        addTorrentPrefilledURL = prefilledURL
        showAddTorrent = true
    }

    /// Entry point for adds that already carry a payload (dropped file, magnet
    /// link, "Open With"). Honours the "Show dialog before adding" app pref:
    /// with the dialog on (the default) the sheet opens prefilled; with it off
    /// the torrent is added immediately with the sheet's defaults (daemon's
    /// default folder, no labels, normal priority, start on). `showDialog`
    /// defaults to the app pref so tests can inject it directly.
    public func addFromExternalURL(
        _ url: URL, showDialog: Bool = UserDefaults.standard.bool(forKey: PreferenceKeys.showAddDialogBeforeAdding)
    ) {
        guard actionsEnabled else { return }
        let isMagnet = url.scheme == "magnet"
        guard isMagnet || url.isFileURL else { return }
        guard showDialog else {
            let deleteAfterAdding = UserDefaults.standard.bool(
                forKey: PreferenceKeys.deleteTorrentFileAfterAdding)
            Task {
                if isMagnet {
                    await add(
                        fileURL: nil, magnetURL: url.absoluteString, destination: "",
                        labels: [], priority: .normal, startWhenAdded: true,
                        deleteFileAfterAdding: deleteAfterAdding)
                } else {
                    await add(
                        fileURL: url, magnetURL: nil, destination: "",
                        labels: [], priority: .normal, startWhenAdded: true,
                        deleteFileAfterAdding: deleteAfterAdding)
                }
            }
            return
        }
        openAddSheet(magnetMode: isMagnet, prefilledURL: url)
    }
    public func openEditLabels(for ids: [Torrent.ID]) {
        guard actionsEnabled, supportsLabels, !ids.isEmpty else { return }
        editLabelsTargetIDs = ids
        showEditLabels = true
    }

    public func openSetLocation(for ids: [Torrent.ID]) {
        guard actionsEnabled, !ids.isEmpty else { return }
        setLocationTargetIDs = ids
        showSetLocation = true
    }

    public func openRenameTorrent(for id: Torrent.ID) {
        guard actionsEnabled else { return }
        renameTorrentTargetID = id
        showRenameTorrent = true
    }

    /// Rename a torrent's root (its display name). `newName` must be a single
    /// path component — no `/`. Returns true on success; surfaces daemon
    /// errors via `lastActionError` like every other mutation.
    @discardableResult
    public func renameTorrent(_ id: Torrent.ID, newName: String) async -> Bool {
        guard let mutations, let current = list.torrents.first(where: { $0.id == id }) else {
            return false
        }
        do {
            try await mutations.renamePath(id, path: current.name, newName: newName)
            await refreshInspectorIfCurrent(id)
            return true
        } catch {
            recordError(error)
            return false
        }
    }

    @discardableResult
    public func setLocation(_ ids: [Torrent.ID], location: String, move: Bool) async -> Bool {
        guard let mutations else { return false }
        do {
            try await mutations.setLocation(ids, location: location, move: move)
            return true
        } catch {
            recordError(error)
            return false
        }
    }

    @discardableResult
    public func add(
        fileURL: URL?,
        magnetURL: String?,
        destination: String,
        labels: [String],
        priority: TorrentPriority,
        startWhenAdded: Bool,
        deleteFileAfterAdding: Bool = false
    ) async -> Bool {
        guard let mutations else { return false }
        do {
            try await mutations.add(
                fileURL: fileURL,
                magnetURL: magnetURL,
                destination: destination,
                labels: labels,
                priority: priority,
                startWhenAdded: startWhenAdded
            )
            if deleteFileAfterAdding, let fileURL {
                deleteLocalTorrentFile(fileURL)
            }
            return true
        } catch {
            recordError(error)
            return false
        }
    }

    /// Best-effort cleanup of the source `.torrent` file after the daemon
    /// accepted it. Restricted to `.torrent` files so a caller mistake can't
    /// delete arbitrary user data; a failure (locked file, lost sandbox
    /// access) is logged and leaves the file in place — the add itself
    /// already succeeded.
    private func deleteLocalTorrentFile(_ url: URL) {
        guard url.isFileURL, url.pathExtension.lowercased() == "torrent" else { return }
        // `.fileImporter` URLs are security-scoped; re-claim access for the
        // deletion (the read inside the service already released its scope).
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            logger.error(
                "Added torrent but failed to delete \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    public func setLabels(_ ids: [Torrent.ID], labels: [String]) async {
        guard let mutations else { return }
        logger.info("setLabels store action: ids=\(ids) labels=\(labels)")
        do {
            try await mutations.setLabels(ids, labels: labels)
            logger.info("setLabels store action succeeded for ids=\(ids)")
        } catch {
            logger.error("setLabels store action failed for ids=\(ids): \(error)")
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

    /// After a mutation that only affects inspector-scoped data, re-fetch the
    /// inspector detail when the mutated torrent is the one currently shown.
    /// Per-file wanted/priority live in `inspectorDetail` — the list poll never
    /// carries `files` — so without this the Files tab shows stale values until
    /// the selection changes.
    private func refreshInspectorIfCurrent(_ id: Torrent.ID) async {
        guard list.selectedTorrents.first?.id == id else { return }
        await fetchInspectorDetail(for: id)
    }

    /// The torrent to resolve a mapping against. From the torrent list the
    /// `files` array isn't fetched, so fetch inspector detail on demand when
    /// `{file}` needs to tell a single-file torrent (open the file) from a
    /// multi-file one (open the folder). Falls back to the list torrent when
    /// the fetch fails or files are already known.
    public func torrentForOpening(_ torrent: Torrent) async -> Torrent {
        if !torrent.files.isEmpty { return torrent }
        return (try? await service.inspectorData(for: torrent.id)) ?? torrent
    }

    public func refreshFreeSpace() async {
        freeSpace = await service.freeSpace()
    }

    /// Fetch current + lifetime transfer stats (`session-stats`) for the
    /// status-bar popover. No-ops when disconnected; silently keeps stale
    /// values if the fetch fails — a failed refresh just shows old numbers,
    /// which doesn't warrant an alert.
    public func refreshSessionStats() async {
        guard isConnected else { return }
        if let stats = await service.sessionStats() {
            sessionStats = stats
        }
    }

    /// Capture an anonymized snapshot of the current daemon state and write it
    /// to `url`. Runs the full pipeline: raw capture → scope (current filters
    /// + torrent limit) → deterministic redaction → leak check → write.
    /// Returns what was redacted and how many torrents made it in, for the
    /// capture-complete alert. `tagColors` (the local tag→colour assignments)
    /// is embedded so replay shows the same colours; it's dropped when the
    /// capture anonymizes names, since fuzzed labels wouldn't match them.
    public func captureSnapshot(
        to url: URL,
        options: SnapshotRedactionOptions = SnapshotRedactionOptions(),
        tagColors: [String: TagColor] = [:]
    ) async throws -> SnapshotCaptureResult {
        let raw = try await service.captureRawSnapshot()
        let visibleOrder = options.respectFilters ? list.visibleTorrents.map(\.id) : nil
        let scoped = SnapshotScope.apply(
            to: raw.torrents, visibleOrder: visibleOrder, maxTorrents: options.maxTorrents
        )
        var scopedRaw = raw
        scopedRaw.torrents = scoped
        scopedRaw.tagColors = options.includeNames ? (tagColors.isEmpty ? nil : tagColors) : nil
        let redactor = SnapshotRedactor(options: options)
        let (tree, summary) = try redactor.redact(scopedRaw)
        try SnapshotLeakChecker.check(
            tree,
            namesKept: options.includeNames,
            anonymizeTrackers: options.anonymizeTrackers
        )
        let data = try JSONSerialization.data(
            withJSONObject: tree,
            options: [.sortedKeys, .prettyPrinted]
        )
        try data.write(to: url, options: .atomic)
        return SnapshotCaptureResult(summary: summary, torrentCount: scoped.count)
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
        list.setTorrents([])
        freeSpace = nil
        daemonVersion = nil
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
