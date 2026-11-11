import Foundation
import Observation

/// Where the add sheet's torrent comes from. A link is either a magnet or an
/// http(s) URL — the daemon treats both the same way (`torrent-add`'s
/// `filename`). Lives in Core because the coordinator picks the initial mode
/// and package code can't see the app's views.
public enum AddTorrentInputMode: Hashable, Sendable, CaseIterable {
    case file, link
}

/// Presentation state for the main window's sheets. A plain state bag: the
/// coordinator's `open*` entry points decide what to show and fill in the
/// targets; the sheets read these bindings.
@MainActor
@Observable
public final class TorrentSheetState {
    // Add-torrent sheet
    public var showAddTorrent = false
    public var addTorrentStartMode: AddTorrentInputMode = .file
    public var addTorrentPrefilledURL: URL?

    // Edit-labels popup
    public var showEditLabels = false
    public var editLabelsTargetIDs: [Torrent.ID] = []

    // Set-location popup
    public var showSetLocation = false
    public var setLocationTargetIDs: [Torrent.ID] = []

    // Rename-torrent popup (single-torrent only — `torrent-rename-path`
    // requires exactly one id)
    public var showRenameTorrent = false
    public var renameTorrentTargetID: Torrent.ID?

    /// Bumped by the Edit menu's Find command. The main window watches it to
    /// focus the search field; a counter keeps repeated presses distinct.
    public private(set) var searchFocusRequest = 0

    public func focusSearch() {
        searchFocusRequest += 1
    }

    public init() {}
}
