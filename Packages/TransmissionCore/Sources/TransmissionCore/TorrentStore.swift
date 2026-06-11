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

    private let service: any TorrentService
    private var streamTask: Task<Void, Never>?

    public init(service: any TorrentService) {
        self.service = service
        startStream()
    }

    private func startStream() {
        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = await self.service.torrentsStream()
            for await snapshot in stream {
                self.torrents = snapshot
                if case .connected = self.connection {
                } else {
                    self.connection = .connected
                }
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

    /// Override the connection state — used by the debug menu (slice 6).
    public func simulateConnection(_ state: ConnectionState) {
        connection = state
    }
}
