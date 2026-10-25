import Foundation
import OSLog
import TransmissionRPC

private let logger = Logger(subsystem: "net.jvacek.TransmissionSwift", category: "core")

public actor RPCTorrentService: TorrentService {
    private let client: any TransmissionClient
    private let pollingInterval: @Sendable () -> TimeInterval
    /// Interval for the active subset between full polls; clamped to
    /// `pollingInterval` so the fast path can never be slower than the base.
    private let activePollingInterval: @Sendable () -> TimeInterval
    private var continuation: AsyncThrowingStream<[Torrent], Error>.Continuation?
    private var pollTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    /// Last full-list snapshot, kept so partial polls can be merged into a
    /// complete array for the store. Idle torrents are not re-fetched.
    private var cache: [Torrent] = []
    private var lastFullPoll: Date?

    /// Cached result from the most recent `session-get`. Updated by `freeSpace()`
    /// which is called on connect and periodically thereafter. Used for:
    ///   - `isAlternativeSpeedEnabled()` — avoids an extra RPC on every read
    ///   - `add()` — gates the `labels` argument on rpcVersion >= 17
    private var cachedSession: SessionInfo?

    public init(
        client: any TransmissionClient,
        pollingInterval: @escaping @Sendable () -> TimeInterval = {
            let v = UserDefaults.standard.double(forKey: PreferenceKeys.pollingIntervalSeconds)
            return v > 0 ? v : 5.0
        },
        activePollingInterval: @escaping @Sendable () -> TimeInterval = {
            let v = UserDefaults.standard.double(forKey: PreferenceKeys.activePollingIntervalSeconds)
            return v > 0 ? v : 1.0
        }
    ) {
        self.client = client
        self.pollingInterval = pollingInterval
        self.activePollingInterval = activePollingInterval
    }

    public func torrentsStream() async -> AsyncThrowingStream<[Torrent], Error> {
        // Unicast: cancel any existing poll loop before handing back a new stream.
        pollTask?.cancel()
        consecutiveFailures = 0
        // A new stream means a new connection; the cached snapshot belongs to
        // the old one, so start with a full poll.
        cache = []
        lastFullPoll = nil
        let (stream, cont) = AsyncThrowingStream<[Torrent], Error>.makeStream()
        self.continuation = cont
        let task = Task { await self.runPollLoop() }
        self.pollTask = task
        // Cancelling the consumer's for-await must cancel the unstructured poll task.
        cont.onTermination = { [task] _ in task.cancel() }
        return stream
    }

    /// Fetches free space and caches the full `SessionInfo` as a side effect.
    /// Called on connect and on a longer interval from `TorrentStore` — this
    /// is the only place `cachedSession` is refreshed, so the cache is as
    /// fresh as the caller's polling cadence.
    public func freeSpace() async -> Int64? {
        // A transient failure must not clobber `cachedSession`: it also backs
        // `supportsLabels()` and `downloadDirectory()`, so wiping it would flip
        // capability detection for a daemon that is merely slow to answer. Keep
        // the last-known-good and return its (stale but usable) free space.
        guard let session = try? await client.sessionGet() else {
            return cachedSession?.downloadDirFreeSpace
        }
        cachedSession = session
        return session.downloadDirFreeSpace
    }

    public func downloadDirectory() async -> String? {
        cachedSession?.downloadDir
    }

    public func supportsLabels() async -> Bool {
        // Optimistic until the first session-get lands (nil cache = don't disable
        // a capability we can't disprove); the store refreshes this alongside
        // freeSpace polling, so it flips to false as soon as an old daemon's
        // rpc-version is known.
        cachedSession.map { $0.rpcVersion >= 17 } ?? true
    }

    public func torrents() async throws -> [Torrent] {
        let resp = try await client.torrentGet(fields: TorrentGetResponse.listFields, ids: nil)
        return resp.torrents.map { Torrent(wire: $0) }
    }

    private func runPollLoop() async {
        while !Task.isCancelled {
            let base = pollingInterval()
            let fast = PollingIntervals.incremental(active: activePollingInterval(), refresh: base)
            let now = Date()
            guard let plan = Self.plan(cache: cache, lastFullPoll: lastFullPoll, base: base, now: now)
            else {
                // Nothing transferring and the full poll isn't due: wait for it.
                let elapsed = lastFullPoll.map { now.timeIntervalSince($0) } ?? base
                try? await Task.sleep(for: .seconds(max(1, base - elapsed)))
                continue
            }
            do {
                let resp = try await client.torrentGet(
                    fields: TorrentGetResponse.listFields,
                    ids: plan == .full ? nil : .recentlyActive)
                let fresh = resp.torrents.map { Torrent(wire: $0) }
                if plan == .full {
                    cache = fresh
                    lastFullPoll = Date()
                } else {
                    cache = Self.merging(fresh, removing: resp.removed ?? [], into: cache)
                }
                consecutiveFailures = 0
                continuation?.yield(cache)
            } catch {
                logger.error("Poll error: \(error)")
                if isFatal(error) {
                    continuation?.finish(throwing: error)
                    return
                }
                consecutiveFailures += 1
                if consecutiveFailures >= 3 {
                    continuation?.finish(throwing: error)
                    return
                }
            }
            try? await Task.sleep(for: .seconds(max(1, cache.contains(where: \.isActive) ? fast : base)))
        }
        continuation?.finish()
    }

    /// One iteration's fetch. Nil from `plan(cache:lastFullPoll:base:now:)` means
    /// there is nothing to fetch before the next full poll is due.
    enum PollPlan: Equatable {
        case full
        case recentlyActive
    }

    /// Full list once per base interval, the daemon's changed set in between.
    /// Files and peers live in the inspector's own fetch; this covers list
    /// fields only.
    static func plan(
        cache: [Torrent], lastFullPoll: Date?, base: TimeInterval, now: Date
    ) -> PollPlan? {
        guard let lastFullPoll, now.timeIntervalSince(lastFullPoll) < base else {
            return .full
        }
        return cache.contains(where: \.isActive) ? .recentlyActive : nil
    }

    /// Overlay a recently-active response on the last full snapshot. Unlike a
    /// partial keyed on cached ids this can bring torrents we have never seen
    /// and ids the daemon removed. Existing entries keep their order; new ones
    /// go on the end until the next full poll restores the daemon's order.
    static func merging(
        _ fresh: [Torrent], removing removed: [Torrent.ID], into cache: [Torrent]
    ) -> [Torrent] {
        let dropped = Set(removed)
        var byID = Dictionary(
            uniqueKeysWithValues: fresh.lazy.filter { !dropped.contains($0.id) }.map { ($0.id, $0) })
        var merged = cache.compactMap { torrent -> Torrent? in
            guard !dropped.contains(torrent.id) else { return nil }
            return byID.removeValue(forKey: torrent.id) ?? torrent
        }
        merged.append(contentsOf: byID.values.sorted { $0.id < $1.id })
        return merged
    }

    private func isFatal(_ error: TransmissionError) -> Bool {
        switch error {
        case .unauthorized:
            return true
        case .network(let urlError):
            return urlError.code == .badURL || urlError.code == .unsupportedURL
        default:
            return false
        }
    }

    // MARK: - Actions

    public func start(_ ids: [Torrent.ID]) async throws {
        try await client.torrentAction("torrent-start", ids: ids)
        await refreshAfterMutation()
    }

    public func stop(_ ids: [Torrent.ID]) async throws {
        try await client.torrentAction("torrent-stop", ids: ids)
        await refreshAfterMutation()
    }

    public func remove(_ ids: [Torrent.ID], deleteLocalData: Bool) async throws {
        try await client.torrentRemove(ids: ids, deleteLocalData: deleteLocalData)
        await refreshAfterMutation()
    }

    public func verify(_ ids: [Torrent.ID]) async throws {
        try await client.torrentAction("torrent-verify", ids: ids)
        await refreshAfterMutation()
    }

    public func reannounce(_ ids: [Torrent.ID]) async throws {
        try await client.torrentAction("torrent-reannounce", ids: ids)
        await refreshAfterMutation()
    }

    public func setFilesWanted(_ id: Torrent.ID, fileIDs: [TorrentFile.ID], wanted: Bool)
        async throws
    {
        // An empty array means "all files" on the wire — skip rather than clobber.
        guard !fileIDs.isEmpty else { return }
        var args = TorrentSetArguments(ids: [id])
        if wanted {
            args.filesWanted = fileIDs
        } else {
            args.filesUnwanted = fileIDs
        }
        try await client.torrentSet(args)
        await refreshAfterMutation()
    }

    public func setFilePriority(
        _ id: Torrent.ID, fileIDs: [TorrentFile.ID], priority: TorrentPriority
    ) async throws {
        guard !fileIDs.isEmpty else { return }
        var args = TorrentSetArguments(ids: [id])
        switch priority {
        case .low: args.priorityLow = fileIDs
        case .normal: args.priorityNormal = fileIDs
        case .high: args.priorityHigh = fileIDs
        }
        try await client.torrentSet(args)
        await refreshAfterMutation()
    }

    public func setPriority(_ ids: [Torrent.ID], priority: TorrentPriority) async throws {
        var args = TorrentSetArguments(ids: ids)
        switch priority {
        case .low: args.bandwidthPriority = -1
        case .normal: args.bandwidthPriority = 0
        case .high: args.bandwidthPriority = 1
        }
        try await client.torrentSet(args)
        await refreshAfterMutation()
    }

    public func setOptions(_ id: Torrent.ID, options: TorrentOptions) async throws {
        var args = TorrentSetArguments(ids: [id])
        args.downloadLimited = options.downloadLimited
        args.downloadLimit = options.downloadLimitKBps
        args.uploadLimited = options.uploadLimited
        args.uploadLimit = options.uploadLimitKBps
        args.honorsSessionLimits = options.honorsSessionLimits
        args.seedRatioLimit = options.seedRatioLimit
        args.seedRatioMode = options.seedRatioLimited ? 1 : 0
        args.seedIdleLimit = options.seedIdleMinutes
        args.seedIdleMode = options.seedIdleLimited ? 1 : 0
        args.peerLimit = options.peerLimit
        try await client.torrentSet(args)
        await refreshAfterMutation()
    }

    public func setSpeedLimits(_ ids: [Torrent.ID], _ patch: TorrentSpeedLimitPatch) async throws {
        guard !ids.isEmpty else { return }
        var args = TorrentSetArguments(ids: ids)
        args.downloadLimited = patch.downloadLimited
        args.downloadLimit = patch.downloadLimitKBps
        args.uploadLimited = patch.uploadLimited
        args.uploadLimit = patch.uploadLimitKBps
        try await client.torrentSet(args)
        await refreshAfterMutation()
    }

    public func setLabels(_ ids: [Torrent.ID], labels: [String]) async throws {
        // Label writes require rpc-version >= 17 (Transmission 4.0). cachedSession
        // is refreshed by freeSpace() on connect and periodically; if it's still
        // missing, fetch once here so a cold cache can't silently no-op the action.
        guard let session = await sessionWarmingCache() else {
            logger.warning(
                "setLabels skipped — session unknown (cannot verify rpc-version); ids=\(ids, privacy: .public)")
            throw TransmissionError.serverError("Cannot verify whether the daemon supports labels (session-get failed)")
        }
        guard session.rpcVersion >= 17 else {
            logger.warning(
                "setLabels skipped — daemon rpc-version \(session.rpcVersion) < 17 does not support labels; ids=\(ids, privacy: .public)"
            )
            throw TransmissionError.serverError(
                "This daemon (rpc-version \(session.rpcVersion)) does not support labels")
        }
        logger.debug("setLabels: ids=\(ids, privacy: .public) labels=\(labels, privacy: .public)")
        var args = TorrentSetArguments(ids: ids)
        args.labels = labels
        try await client.torrentSet(args)
        logger.debug("setLabels succeeded for ids=\(ids, privacy: .public)")
        await refreshAfterMutation()
    }

    public func setLocation(_ ids: [Torrent.ID], location: String, move: Bool) async throws {
        let args = TorrentSetLocationArguments(ids: ids, location: location, move: move)
        try await client.torrentSetLocation(args)
        await refreshAfterMutation()
    }

    public func renamePath(_ id: Torrent.ID, path: String, newName: String) async throws {
        let args = TorrentRenamePathArguments(ids: [id], path: path, name: newName)
        _ = try await client.torrentRenamePath(args)
        await refreshAfterMutation()
    }

    public func setAlternativeSpeedEnabled(_ enabled: Bool) async throws {
        try await client.sessionSet(SessionSetArguments(altSpeedEnabled: enabled))
    }

    public func isAlternativeSpeedEnabled() async -> Bool {
        // A freshly constructed service (App Intents, no connect flow) starts
        // with a cold cache; reading `nil` would report "off" for a daemon whose
        // turtle mode is on, and the toggle-on-read would then no-op. Warm once.
        await sessionWarmingCache()?.altSpeedEnabled ?? false
    }

    /// The cached `session-get`, fetching it once when the cache is cold.
    /// Returns nil only when the daemon doesn't answer. Callers that must not
    /// proceed on unknown session state can treat nil as an error.
    private func sessionWarmingCache() async -> SessionInfo? {
        if let cached = cachedSession { return cached }
        let fetched = try? await client.sessionGet()
        cachedSession = fetched
        return fetched
    }

    public func daemonVersion() async -> String? {
        cachedSession?.version
    }

    public func sessionSettings() async -> SessionSettings? {
        // Warm a cold cache from a fresh session-get so mocked/empty state
        // doesn't read stale or nil values.
        guard let session = await sessionWarmingCache() else { return nil }
        return SessionSettings(wire: session)
    }

    public func applySessionSettings(_ patch: SessionSettingsPatch) async throws {
        guard !patch.isEmpty else { return }
        var args = SessionSetArguments()
        patch.apply(to: &args)
        logger.info("applySessionSettings: \(String(describing: args), privacy: .public)")
        try await client.sessionSet(args)
        // Refresh the cache so subsequent reads reflect the written state.
        if let fetched = try? await client.sessionGet() {
            cachedSession = fetched
        }
    }

    public func isPortOpen() async -> Bool? {
        try? await client.portTest()
    }

    public func sessionStats() async -> SessionStats? {
        try? await client.sessionStats()
    }

    public func inspectorData(for id: Torrent.ID) async throws -> Torrent {
        let fields = TorrentGetResponse.listFields + TorrentGetResponse.inspectorFields
        let resp = try await client.torrentGet(fields: fields, ids: .list([id]))
        guard let wire = resp.torrents.first else {
            throw TransmissionError.serverError("No torrent returned for id \(id)")
        }
        return Torrent(wire: wire)
    }

    public func add(
        fileURL: URL?,
        magnetURL: String?,
        destination: String,
        labels: [String],
        priority: TorrentPriority,
        startWhenAdded: Bool
    ) async throws {
        let filename: String?
        let metainfo: String?

        if let magnetURL {
            filename = magnetURL
            metainfo = nil
        } else if let fileURL {
            // URLs from SwiftUI's `.fileImporter` are security-scoped; reading
            // them without claiming access fails with NSFileReadNoPermissionError
            // ("you don't have permission to view it"), even outside the sandbox.
            let scoped = fileURL.startAccessingSecurityScopedResource()
            defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: fileURL)
            metainfo = data.base64EncodedString()
            filename = nil
        } else {
            filename = nil
            metainfo = nil
        }

        let bandwidthPriority: Int
        switch priority {
        case .low: bandwidthPriority = -1
        case .normal: bandwidthPriority = 0
        case .high: bandwidthPriority = 1
        }

        let wireLabels: [String]?
        if !labels.isEmpty {
            // Label support is gated on rpc-version. Warm a cold cache first so a
            // fresh service (App Intents) can't silently drop the labels; if the
            // session can't be read we fail rather than add without them.
            guard let session = await sessionWarmingCache() else {
                throw TransmissionError.serverError(
                    "Cannot verify whether the daemon supports labels (session-get failed)")
            }
            wireLabels = session.rpcVersion >= 17 ? labels : nil
        } else {
            wireLabels = nil
        }

        let args = TorrentAddArguments(
            filename: filename,
            metainfo: metainfo,
            downloadDir: destination.isEmpty ? nil : destination,
            paused: !startWhenAdded,
            bandwidthPriority: bandwidthPriority,
            labels: wireLabels
        )
        let response = try await client.torrentAdd(args)
        if let dup = response.torrentDuplicate {
            throw TransmissionError.torrentDuplicate(name: dup.name)
        }
        await refreshAfterMutation()
    }

    // MARK: - Snapshot capture

    public func captureRawSnapshot() async throws -> SnapshotFile {
        // The union of list + inspector fields: the snapshot is wire-shaped, so
        // replay decodes through the exact same path as a live poll.
        let fields = TorrentGetResponse.listFields + TorrentGetResponse.inspectorFields
        let response = try await client.torrentGet(fields: fields, ids: nil)
        let session = try await client.sessionGet()
        return SnapshotFile(
            version: snapshotFormatVersion,
            capturedAt: ISO8601DateFormatter().string(from: Date()),
            source: SnapshotSourceInfo(
                daemonVersion: session.version,
                rpcVersion: session.rpcVersion,
                redacted: false
            ),
            session: session,
            torrents: response.torrents,
            redactions: nil
        )
    }

    // MARK: - Post-mutation refresh

    /// After a mutation RPC succeeds, immediately re-fetch and yield a fresh
    /// snapshot so the UI reflects the change without waiting for the next poll
    /// tick. Best-effort — a failed refresh is harmless because the poll loop
    /// picks the change up shortly. The mutation RPCs return no state (spec
    /// §3.1–3.4 "Response arguments: none"), so this second `torrent-get` is
    /// unavoidable.
    private func refreshAfterMutation() async {
        do {
            let snapshot = try await torrents()
            cache = snapshot
            lastFullPoll = Date()
            continuation?.yield(cache)
            logger.debug("Post-mutation refresh yielded \(snapshot.count) torrents")
        } catch {
            logger.error("Post-mutation refresh failed: \(error)")
        }
    }
}
