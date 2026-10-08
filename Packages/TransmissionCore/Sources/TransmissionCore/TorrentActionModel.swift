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
        do { try await mutations.remove(ids, deleteLocalData: deleteLocalData) } catch { report(error) }
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

    public func setLabels(_ ids: [Torrent.ID], labels: [String]) async {
        guard let mutations else { return }
        logger.info("setLabels store action: ids=\(ids) labels=\(labels)")
        do {
            try await mutations.setLabels(ids, labels: labels)
            logger.info("setLabels store action succeeded for ids=\(ids)")
        } catch {
            logger.error("setLabels store action failed for ids=\(ids): \(error)")
            report(error)
        }
    }

    // MARK: - Location / rename / add

    @discardableResult
    public func setLocation(_ ids: [Torrent.ID], location: String, move: Bool) async -> Bool {
        guard let mutations else { return false }
        do {
            try await mutations.setLocation(ids, location: location, move: move)
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Rename a torrent's root (its display name). `newName` must be a single
    /// path component — no `/`. Returns true on success; surfaces daemon errors
    /// via the coordinator's `lastActionError` like every other mutation.
    @discardableResult
    public func renameTorrent(_ id: Torrent.ID, newName: String) async -> Bool {
        guard let mutations, let current = list.torrents.first(where: { $0.id == id }) else {
            return false
        }
        do {
            try await mutations.renamePath(id, path: current.name, newName: newName)
            await inspector.refreshIfShowing(id)
            return true
        } catch {
            report(error)
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
            report(error)
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

    private func report(_ error: any Error) {
        onError?(ActionError.from(error))
    }
}
