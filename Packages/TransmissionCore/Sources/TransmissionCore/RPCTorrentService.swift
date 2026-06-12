import Foundation
import OSLog
import TransmissionRPC

private let logger = Logger(subsystem: "net.jvacek.TransmissionSwift", category: "core")

public actor RPCTorrentService: TorrentService {
    private let client: any TransmissionClient
    private let pollingInterval: @Sendable () -> TimeInterval
    private var continuation: AsyncThrowingStream<[Torrent], Error>.Continuation?
    private var pollTask: Task<Void, Never>?
    private var consecutiveFailures = 0

    /// Cached result from the most recent `session-get`. Updated by `freeSpace()`
    /// which is called on connect and periodically thereafter. Used for:
    ///   - `isAlternativeSpeedEnabled()` — avoids an extra RPC on every read
    ///   - `add()` — gates the `labels` argument on rpcVersion >= 17
    private var cachedSession: SessionInfo?

    public init(
        client: any TransmissionClient,
        pollingInterval: @escaping @Sendable () -> TimeInterval = {
            let v = UserDefaults.standard.double(forKey: "pollingIntervalSeconds")
            return v > 0 ? v : 5.0
        }
    ) {
        self.client = client
        self.pollingInterval = pollingInterval
    }

    public func torrentsStream() async -> AsyncThrowingStream<[Torrent], Error> {
        // Unicast: cancel any existing poll loop before handing back a new stream.
        pollTask?.cancel()
        consecutiveFailures = 0
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
        let session = try? await client.sessionGet()
        cachedSession = session
        return session?.downloadDirFreeSpace
    }

    public func downloadDirectory() async -> String? {
        cachedSession?.downloadDir
    }

    public func torrents() async throws -> [Torrent] {
        let resp = try await client.torrentGet(fields: TorrentGetResponse.listFields, ids: nil)
        return resp.torrents.map { Torrent(wire: $0) }
    }

    private func runPollLoop() async {
        while !Task.isCancelled {
            do {
                let snapshot = try await torrents()
                consecutiveFailures = 0
                continuation?.yield(snapshot)
            } catch {
                logger.error("Poll error: \(error)")
                let txError = error as? TransmissionError
                if let txError, isFatal(txError) {
                    continuation?.finish(throwing: txError)
                    return
                }
                consecutiveFailures += 1
                if consecutiveFailures >= 3 {
                    continuation?.finish(throwing: error)
                    return
                }
            }
            try? await Task.sleep(for: .seconds(max(1, pollingInterval())))
        }
        continuation?.finish()
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
    }

    public func stop(_ ids: [Torrent.ID]) async throws {
        try await client.torrentAction("torrent-stop", ids: ids)
    }

    public func remove(_ ids: [Torrent.ID], deleteLocalData: Bool) async throws {
        try await client.torrentRemove(ids: ids, deleteLocalData: deleteLocalData)
    }

    public func verify(_ ids: [Torrent.ID]) async throws {
        try await client.torrentAction("torrent-verify", ids: ids)
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
    }

    public func setAlternativeSpeedEnabled(_ enabled: Bool) async throws {
        try await client.sessionSet(SessionSetArguments(altSpeedEnabled: enabled))
    }

    public func isAlternativeSpeedEnabled() async -> Bool {
        cachedSession?.altSpeedEnabled ?? false
    }

    public func inspectorData(for id: Torrent.ID) async throws -> Torrent {
        let fields = TorrentGetResponse.listFields + TorrentGetResponse.inspectorFields
        let resp = try await client.torrentGet(fields: fields, ids: [id])
        guard let wire = resp.torrents.first else {
            throw TransmissionError.serverError("No torrent returned for id \(id)")
        }
        return Torrent(wire: wire)
    }

    public func add(
        fileURL: URL?,
        magnetURL: String?,
        destination: String,
        label: String?,
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

        let labels: [String]?
        if let label, !label.isEmpty, (cachedSession?.rpcVersion ?? 0) >= 17 {
            labels = [label]
        } else {
            labels = nil
        }

        let args = TorrentAddArguments(
            filename: filename,
            metainfo: metainfo,
            downloadDir: destination.isEmpty ? nil : destination,
            paused: !startWhenAdded,
            bandwidthPriority: bandwidthPriority,
            labels: labels
        )
        let response = try await client.torrentAdd(args)
        if let dup = response.torrentDuplicate {
            throw TransmissionError.torrentDuplicate(name: dup.name)
        }
        // Success: surface the new torrent immediately instead of waiting for the
        // next poll tick. Best-effort — a failed refresh is harmless since the
        // poll loop will pick it up shortly.
        if let snapshot = try? await torrents() {
            continuation?.yield(snapshot)
        }
    }
}
