// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import OSLog
import Observation

private let logger = Logger(subsystem: "net.jvacek.TransmissionSwift", category: "actions")

/// Every torrent mutation: start/stop/verify/re-announce, per-file and
/// per-torrent options, labels, location, rename, add, and the staged remove
/// confirmation.
///
/// Holds the list model (to prune selection on remove) and the inspector model
/// (to refresh detail after file/rename mutations). The coordinator binds the
/// current mutation service on connect and receives failures through
/// `onError`, which it surfaces as `lastActionError`.
@MainActor
@Observable
public final class TorrentActionModel {
    /// A removal awaiting user confirmation, driving `.confirmationDialog(item:)`.
    public var pendingRemoval: PendingRemoval?

    var onError: ((ActionError) -> Void)?

    private let list: TorrentListModel
    private let inspector: InspectorModel
    private var mutations: (any TorrentMutating)?

    init(list: TorrentListModel, inspector: InspectorModel) {
        self.list = list
        self.inspector = inspector
    }

    func connect(mutations: (any TorrentMutating)?) {
        self.mutations = mutations
    }

    // MARK: - Simple actions

    public func start(_ ids: [Torrent.ID]) async {
        guard let mutations else { return }
        do { try await mutations.start(ids) } catch { report(error) }
    }

    public func stop(_ ids: [Torrent.ID]) async {
        guard let mutations else { return }
        do { try await mutations.stop(ids) } catch { report(error) }
    }

    public func remove(_ ids: [Torrent.ID], deleteLocalData: Bool = false) async {
        guard let mutations else { return }
        do {
            try await mutations.remove(ids, deleteLocalData: deleteLocalData)
            // Only drop the selection once the daemon accepted the removal; a
            // failed remove leaves the torrents in place, so keep them selected.
            list.selectedTorrentIDs.subtract(ids)
        } catch {
            report(error)
        }
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
        guard mutations != nil, !ids.isEmpty else { return }
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
        do { try await mutations.verify(ids) } catch { report(error) }
    }

    public func reannounce(_ ids: [Torrent.ID]) async {
        guard let mutations else { return }
        do { try await mutations.reannounce(ids) } catch { report(error) }
    }

    // MARK: - Options

    public func setFilesWanted(_ id: Torrent.ID, fileIDs: [TorrentFile.ID], wanted: Bool) async {
        guard let mutations else { return }
        do {
            try await mutations.setFilesWanted(id, fileIDs: fileIDs, wanted: wanted)
            await inspector.refreshIfShowing(id)
        } catch { report(error) }
    }

    public func setFilePriority(
        _ id: Torrent.ID, fileIDs: [TorrentFile.ID], priority: TorrentPriority
    ) async {
        guard let mutations else { return }
        do {
            try await mutations.setFilePriority(id, fileIDs: fileIDs, priority: priority)
            await inspector.refreshIfShowing(id)
        } catch { report(error) }
    }

    public func setPriority(_ ids: [Torrent.ID], priority: TorrentPriority) async {
        guard let mutations else { return }
        do { try await mutations.setPriority(ids, priority: priority) } catch { report(error) }
    }

    public func setOptions(_ id: Torrent.ID, options: TorrentOptions) async {
        guard let mutations else { return }
        do { try await mutations.setOptions(id, options: options) } catch { report(error) }
    }

    /// Replace the label set on every torrent in `ids`.
    public func setLabels(_ ids: [Torrent.ID], labels: [String]) async throws(ActionError) {
        let mutations = try connected()
        logger.info("setLabels store action: ids=\(ids) labels=\(labels)")
        do {
            try await mutations.setLabels(ids, labels: labels)
        } catch {
            logger.error("setLabels store action failed for ids=\(ids): \(error)")
            throw .from(error)
        }
    }

    // MARK: - Trackers

    /// Add one announce URL to a torrent's tracker list (into its last tier).
    public func addTracker(_ id: Torrent.ID, announce: String) async throws(ActionError) {
        try await editTrackers(id) { TrackerList.adding(announce, to: $0) }
    }

    /// Remove one tracker by its announce URL.
    public func removeTracker(_ id: Torrent.ID, _ tracker: Tracker) async throws(ActionError) {
        try await editTrackers(id) { TrackerList.removing(tracker.announce, from: $0) }
    }

    /// Move one tracker into another tier. An existing tier joins it (the two
    /// then race); a tier past the last one becomes a new backup tier.
    public func moveTracker(_ id: Torrent.ID, _ tracker: Tracker, toTier tier: Int) async throws(ActionError) {
        try await editTrackers(id) { TrackerList.moving(tracker.announce, toTier: tier, in: $0) }
    }

    /// Point one tracker at a different announce URL, keeping its tier. This is
    /// what a private torrent needs when its tracker moves domains.
    public func replaceTracker(
        _ id: Torrent.ID, _ tracker: Tracker, announce: String
    ) async throws(ActionError) {
        try await editTrackers(id) {
            TrackerList.replacing(tracker.announce, with: announce, in: $0)
        }
    }

    /// The announce list is a whole-set write, so every edit reads the trackers
    /// from the last poll, rebuilds the string and sends it back.
    private func editTrackers(
        _ id: Torrent.ID, _ edit: ([Tracker]) -> String
    ) async throws(ActionError) {
        let mutations = try connected()
        let torrent = try listed(id)
        do {
            try await mutations.setTrackerList(id, to: edit(torrent.trackers))
        } catch {
            throw .from(error)
        }
    }

    // MARK: - Location / rename / add

    public func setLocation(_ ids: [Torrent.ID], location: String, move: Bool) async throws(ActionError) {
        let mutations = try connected()
        do {
            try await mutations.setLocation(ids, location: location, move: move)
        } catch {
            throw .from(error)
        }
    }

    /// Rename a torrent's root (its display name). `newName` must be a single
    /// path component — no `/`.
    public func renameTorrent(_ id: Torrent.ID, newName: String) async throws(ActionError) {
        let mutations = try connected()
        let current = try listed(id)
        do {
            try await mutations.renamePath(id, path: current.name, newName: newName)
        } catch {
            throw .from(error)
        }
        await inspector.refreshIfShowing(id)
    }

    public func add(
        fileURL: URL?,
        linkURL: String?,
        destination: String,
        labels: [String],
        priority: TorrentPriority,
        startWhenAdded: Bool,
        files: [TorrentAddFile] = [],
        deleteFileAfterAdding: Bool = false
    ) async throws(ActionError) {
        guard let mutations else { throw .from(TorrentAddError.notConnected) }
        do {
            try await mutations.add(
                fileURL: fileURL,
                linkURL: linkURL,
                destination: destination,
                labels: labels,
                priority: priority,
                startWhenAdded: startWhenAdded,
                files: files
            )
        } catch {
            throw .from(error)
        }
        if deleteFileAfterAdding, let fileURL {
            deleteLocalTorrentFile(fileURL)
        }
    }

    /// Runs a throwing action for a caller with nowhere to show the error
    /// inline (a context menu, a dropped file), so a failure goes to the
    /// app-wide alert instead. Sheets catch the error themselves.
    public func reportingFailure(_ action: () async throws -> Void) async {
        do {
            try await action()
        } catch {
            report(error)
        }
    }

    private func connected() throws(ActionError) -> any TorrentMutating {
        guard let mutations else { throw .failed(message: "Not connected to a server.") }
        return mutations
    }

    private func listed(_ id: Torrent.ID) throws(ActionError) -> Torrent {
        guard let torrent = list.torrents.first(where: { $0.id == id }) else {
            throw .failed(message: "The torrent is no longer in the list.")
        }
        return torrent
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

    private func report(_ error: any Error) {
        onError?(ActionError.from(error))
    }
}
