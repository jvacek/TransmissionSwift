import Foundation
import OSLog
import Observation

private let logger = Logger(subsystem: "net.jvacek.TransmissionSwift", category: "inspector")

/// The inspector pane's state: the fully-populated torrent currently shown, its
/// visibility (a persisted preference) and its selected tab, plus the fetch
/// that keeps the detail current.
///
/// The coordinator binds the current read service on connect and drives the
/// post-mutation refresh through `refreshIfShowing(_:)`, which consults the list
/// model's selection.
@MainActor
@Observable
public final class InspectorModel {
    /// Torrent fetched with full inspector fields for the selected torrent.
    /// Nil when no torrent is selected or before the first fetch. Not wiped by
    /// the list poll — updated only by `fetch(for:)`.
    public private(set) var detail: Torrent?
    public var isVisible: Bool = true {
        didSet {
            if oldValue != isVisible {
                UserDefaults.standard.set(isVisible, forKey: PreferenceKeys.inspectorVisible)
            }
        }
    }
    public var tab: InspectorTab = .general

    private let list: TorrentListModel
    private var reading: (any TorrentReading)?

    public init(list: TorrentListModel) {
        self.list = list
        if UserDefaults.standard.object(forKey: PreferenceKeys.inspectorVisible) != nil {
            self.isVisible = UserDefaults.standard.bool(forKey: PreferenceKeys.inspectorVisible)
        }
    }

    func connect(reading: any TorrentReading) {
        self.reading = reading
    }

    /// Fetch inspector-level detail (files, peers, trackerStats) for one torrent.
    /// Clears stale detail first if the ID changed. Silently swallows errors —
    /// the tabs fall back to showing empty arrays if the fetch fails.
    public func fetch(for id: Torrent.ID) async {
        guard let reading else { return }
        if detail?.id != id {
            detail = nil
        }
        do {
            let fetched = try await reading.inspectorData(for: id)
            logger.debug(
                "Inspector fetch succeeded for id \(id): \(fetched.files.count) files, \(fetched.peers.count) peers, \(fetched.trackers.count) trackers"
            )
            detail = fetched
        } catch {
            logger.error("Inspector fetch failed for id \(id): \(error)")
        }
    }

    /// After a mutation that only affects inspector-scoped data, re-fetch the
    /// detail when the mutated torrent is the one currently shown. Per-file
    /// wanted/priority live in `detail` — the list poll never carries `files` —
    /// so without this the Files tab shows stale values until the selection
    /// changes.
    func refreshIfShowing(_ id: Torrent.ID) async {
        guard list.selectedTorrents.first?.id == id else { return }
        await fetch(for: id)
    }
}
