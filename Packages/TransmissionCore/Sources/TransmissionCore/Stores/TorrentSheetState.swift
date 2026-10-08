import Foundation
import Observation

/// Presentation state for the main window's sheets. A plain state bag: the
/// coordinator's `open*` entry points decide what to show and fill in the
/// targets; the sheets read these bindings.
@MainActor
@Observable
public final class TorrentSheetState {
    // Add-torrent sheet
    public var showAddTorrent = false
    public var addTorrentStartInMagnetMode = false
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

    public init() {}
}
