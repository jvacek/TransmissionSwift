import Foundation
import Observation
import TransmissionRPC

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

    /// Map any thrown error to the alert to show.
    public static func from(_ error: any Error) -> ActionError {
        if case .torrentDuplicate(let name) = error as? TransmissionError {
            return .torrentDuplicate(name: name)
        }
        return .failed(message: error.localizedDescription)
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
/// (e.g. `store.list.visibleTorrents`, `store.session.freeSpace`,
/// `store.actions.start(_:)`).
@MainActor
@Observable
public final class TorrentStore {
    /// The torrent list and everything derived from it: rows, facets,
    /// selection, search, filters, sort.
    public let list: TorrentListModel
    /// The connected daemon's session-level state and reads/writes.
    public let session = SessionModel()
    /// The inspector pane's detail, visibility and tab.
    public let inspector: InspectorModel
    /// Every torrent mutation, plus the staged remove confirmation.
    public let actions: TorrentActionModel
    /// Presentation state for the main window's sheets.
    public let ui = TorrentSheetState()

    public private(set) var connection: ConnectionState = .connecting
    /// Non-nil when a user action failed. Cleared by the view when the alert is dismissed.
    public var lastActionError: ActionError?

    /// True while the app has a live connection to a daemon. Gates any
    /// session-side setting that can only be read/changed when connected.
    public var isConnected: Bool {
        connection.isConnected
    }

    /// True when the backing service supports mutation actions.
    public private(set) var actionsEnabled: Bool = true

    private var service: any TorrentReading
    private var streamTask: Task<Void, Never>?
    private var freeSpaceTask: Task<Void, Never>?

    public init(service: any TorrentReading) {
        let list = TorrentListModel()
        self.list = list
        let inspector = InspectorModel(list: list)
        self.inspector = inspector
        self.actions = TorrentActionModel(list: list, inspector: inspector)
        self.service = service
        let mutations = service.mutations
        self.actionsEnabled = mutations != nil
        session.connect(reading: service, mutations: mutations)
        session.onError = { [weak self] in self?.lastActionError = $0 }
        actions.connect(mutations: mutations)
        actions.onError = { [weak self] in self?.lastActionError = $0 }
        inspector.connect(reading: service)
        startStream()
    }

    /// Suspend polling while the app is in the background. Cancels the stream
    /// and free-space tasks without changing the connection state.
    public func pausePolling() {
        streamTask?.cancel()
        freeSpaceTask?.cancel()
    }

    /// Resume polling after returning to the foreground. Restarts the stream
    /// from scratch, which also re-fetches free space and alt-speed state.
    ///
    /// No-op unless a stream was already live (`.connecting`/`.connected`). From
    /// `.disconnected` or `.awaitingKeychain` a restart would drive the no-server
    /// placeholder service back to `.connected`, masking the failure. Recovering
    /// from those states is `ConnectionCoordinator`'s job, via the Reconnect button.
    public func resumePolling() {
        guard connection == .connecting || connection.isConnected else { return }
        startStream()
    }

    /// Swap the backing service and restart the poll stream. Used when the
    /// active server profile changes at runtime (first-run or server switching).
    public func connect(service: any TorrentReading) {
        streamTask?.cancel()
        freeSpaceTask?.cancel()
        self.service = service
        let mutations = service.mutations
        actionsEnabled = mutations != nil
        session.connect(reading: service, mutations: mutations)
        session.reset()
        actions.connect(mutations: mutations)
        inspector.connect(reading: service)
        connection = .connecting
        list.setDownloadDirectory(nil)
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
            // freeSpace() also warms the session cache in RPCTorrentService;
            // `session.load` runs it first, so the cache-backed reads after it
            // see warm values.
            await self.session.load(from: capturedService)
            self.list.setDownloadDirectory(await capturedService.downloadDirectory())
            guard !Task.isCancelled else { return }
            self.startFreeSpacePoll()
            do {
                for try await snapshot in stream {
                    self.list.setTorrents(snapshot)
                    // Only write once: a poll tick must not churn observers.
                    if self.connection != .connected {
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
                await self.session.poll(from: capturedService)
            }
        }
    }

    // MARK: - Sheet entry points

    public func openAddSheet(magnetMode: Bool = false, prefilledURL: URL? = nil) {
        ui.addTorrentStartInMagnetMode = magnetMode
        ui.addTorrentPrefilledURL = prefilledURL
        ui.showAddTorrent = true
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
                    await actions.add(
                        fileURL: nil, magnetURL: url.absoluteString, destination: "",
                        labels: [], priority: .normal, startWhenAdded: true,
                        deleteFileAfterAdding: deleteAfterAdding)
                } else {
                    await actions.add(
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
        guard actionsEnabled, session.supportsLabels, !ids.isEmpty else { return }
        ui.editLabelsTargetIDs = ids
        ui.showEditLabels = true
    }

    public func openSetLocation(for ids: [Torrent.ID]) {
        guard actionsEnabled, !ids.isEmpty else { return }
        ui.setLocationTargetIDs = ids
        ui.showSetLocation = true
    }

    public func openRenameTorrent(for id: Torrent.ID) {
        guard actionsEnabled else { return }
        ui.renameTorrentTargetID = id
        ui.showRenameTorrent = true
    }

    // MARK: - Service reads

    /// The torrent to resolve a mapping against. From the torrent list the
    /// `files` array isn't fetched, so fetch inspector detail on demand when
    /// `{file}` needs to tell a single-file torrent (open the file) from a
    /// multi-file one (open the folder). Falls back to the list torrent when
    /// the fetch fails or files are already known.
    public func torrentForOpening(_ torrent: Torrent) async -> Torrent {
        if !torrent.files.isEmpty { return torrent }
        return (try? await service.inspectorData(for: torrent.id)) ?? torrent
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

    // MARK: - Connection state

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
        session.reset()
    }

    /// Override the connection state — used by the debug menu (slice 6).
    public func simulateConnection(_ state: ConnectionState) {
        connection = state
    }
}
