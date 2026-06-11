import Foundation
import Observation

/// The single source of truth the UI binds to. Wraps a `TorrentService`,
/// owns selection / search / filter / inspector state, and derives the
/// sidebar facets and visible-row set.
///
/// Views read this from the environment. View models stay thin.
@MainActor
@Observable
public final class TorrentStore {
    public private(set) var torrents: [Torrent] = []
    public private(set) var connection: ConnectionState = .connecting
    public private(set) var isAlternativeSpeedEnabled: Bool = false
    /// True when the backing service supports mutation actions (mock mode or once 7b lands).
    public private(set) var actionsEnabled: Bool = true
    /// Free space (bytes) on the daemon's download directory. Nil until the first poll completes.
    public private(set) var freeSpace: Int64? = nil

    public var selectedFilter: SidebarFilter = .status(.all)
    public var selectedTorrentIDs: Set<Torrent.ID> = []
    public var searchQuery: String = ""
    public var inspectorVisible: Bool = true
    public var inspectorTab: InspectorTab = .general

    // Add-torrent sheet
    public var showAddTorrent: Bool = false
    public var addTorrentStartInMagnetMode: Bool = false
    public var addTorrentPrefilledURL: URL? = nil

    public var facets: FilterFacets { FilterFacets(torrents: torrents) }

    public var visibleTorrents: [Torrent] {
        torrents.filtered(by: selectedFilter).searched(searchQuery)
    }

    public var selectedTorrents: [Torrent] {
        torrents.filter { selectedTorrentIDs.contains($0.id) }
    }

    private var service: any TorrentService
    private var streamTask: Task<Void, Never>?
    private var freeSpaceTask: Task<Void, Never>?

    public init(service: any TorrentService) {
        self.service = service
        self.actionsEnabled = service.supportsActions
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
        torrents = []
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
            self.freeSpace = await capturedService.freeSpace()
            guard !Task.isCancelled else { return }
            self.startFreeSpacePoll()
            for await snapshot in stream {
                self.torrents = snapshot
                if case .connected = self.connection {
                } else {
                    self.connection = .connected
                }
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

    // MARK: - Actions

    public func start(_ ids: [Torrent.ID]) async {
        try? await service.start(ids)
    }

    public func stop(_ ids: [Torrent.ID]) async {
        try? await service.stop(ids)
    }

    public func remove(_ ids: [Torrent.ID], deleteLocalData: Bool = false) async {
        try? await service.remove(ids, deleteLocalData: deleteLocalData)
        selectedTorrentIDs.subtract(ids)
    }

    public func verify(_ ids: [Torrent.ID]) async {
        try? await service.verify(ids)
    }

    public func setFilesWanted(_ id: Torrent.ID, fileIDs: [TorrentFile.ID], wanted: Bool) async {
        try? await service.setFilesWanted(id, fileIDs: fileIDs, wanted: wanted)
    }

    public func setFilePriority(
        _ id: Torrent.ID, fileIDs: [TorrentFile.ID], priority: TorrentPriority
    ) async {
        try? await service.setFilePriority(id, fileIDs: fileIDs, priority: priority)
    }

    public func setOptions(_ id: Torrent.ID, options: TorrentOptions) async {
        try? await service.setOptions(id, options: options)
    }

    public func toggleAlternativeSpeed() async {
        let newValue = !isAlternativeSpeedEnabled
        try? await service.setAlternativeSpeedEnabled(newValue)
        isAlternativeSpeedEnabled = newValue
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
        try? await service.add(
            fileURL: fileURL,
            magnetURL: magnetURL,
            destination: destination,
            label: label,
            priority: priority,
            startWhenAdded: startWhenAdded
        )
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
}
