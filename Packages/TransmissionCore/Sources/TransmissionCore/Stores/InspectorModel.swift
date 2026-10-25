import Foundation
import OSLog
import Observation

private let logger = Logger(subsystem: "net.jvacek.TransmissionSwift", category: "inspector")

/// The inspector pane's state: the fully-populated torrent currently shown, its
/// visibility (a persisted preference) and its selected tab, plus the fetch
/// that keeps the detail current.
///
/// The coordinator binds the current read service on connect, drives the
/// periodic refresh through `poll()` off the list tick, and the post-mutation
/// refresh through `refreshIfShowing(_:)`. Both consult the list model's
/// selection.
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
                defaults.set(isVisible, forKey: PreferenceKeys.inspectorVisible)
            }
        }
    }
    public var tab: InspectorTab = .general

    private let list: TorrentListModel
    /// Where the visibility preference lives. Injected so tests don't touch (or
    /// depend on) the developer's real preference.
    private let defaults: UserDefaults
    private var reading: (any TorrentReading)?
    /// Bumped per fetch so a slow response can't overwrite a newer one. Poll
    /// ticks and post-mutation refreshes overlap, and the loser would flip a
    /// freshly toggled checkbox back to its pre-mutation state.
    private var fetchGeneration = 0
    /// Set while a fetch is in flight so a slow daemon doesn't pile up requests.
    private var isFetching = false
    /// List snapshot the current detail was fetched from. A tick that moved no
    /// list field has no new files or peers to fetch.
    private var lastPolledSnapshot: Torrent?

    public init(list: TorrentListModel, defaults: UserDefaults = .standard) {
        self.list = list
        self.defaults = defaults
        if defaults.object(forKey: PreferenceKeys.inspectorVisible) != nil {
            self.isVisible = defaults.bool(forKey: PreferenceKeys.inspectorVisible)
        }
    }

    func connect(reading: any TorrentReading) {
        self.reading = reading
        // Detail belongs to the previous server; a same-id torrent on the new
        // one would otherwise show its files until the first fetch lands.
        detail = nil
        lastPolledSnapshot = nil
    }

    /// Fetch inspector-level detail (files, peers, trackerStats) for one torrent.
    /// Clears stale detail first if the ID changed. Errors are logged and
    /// swallowed — the tabs fall back to empty arrays — but reported to the
    /// caller so `poll()` can retry instead of treating the tick as done.
    @discardableResult
    public func fetch(for id: Torrent.ID) async -> Bool {
        guard let reading else { return false }
        if detail?.id != id {
            detail = nil
        }
        fetchGeneration += 1
        let generation = fetchGeneration
        isFetching = true
        defer { isFetching = false }
        do {
            let fetched = try await reading.inspectorData(for: id)
            // A newer fetch owns the result; this one is stale.
            guard generation == fetchGeneration else { return false }
            // An unchanged result must not churn observers: `detail` feeds the
            // inspector's tables, which would otherwise rebuild every tick.
            if fetched != detail {
                logger.debug(
                    "Inspector fetch succeeded for id \(id): \(fetched.files.count) files, \(fetched.peers.count) peers, \(fetched.trackers.count) trackers"
                )
                detail = fetched
            }
            return true
        } catch {
            logger.error("Inspector fetch failed for id \(id): \(error)")
            return false
        }
    }

    /// One refresh driven by the list tick. The list snapshot carries no
    /// files/peers, so the detail pane needs its own request; a tick where the
    /// selected torrent didn't change has nothing new to fetch.
    func poll() async {
        guard isVisible, !isFetching, let torrent = list.selectedTorrents.first else { return }
        guard torrent != lastPolledSnapshot else { return }
        // Record only a completed fetch: a failure must stay eligible so the
        // next tick retries rather than showing empty tabs until the torrent
        // changes.
        if await fetch(for: torrent.id) {
            lastPolledSnapshot = torrent
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
