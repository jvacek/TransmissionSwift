import Foundation
import OSLog
import TransmissionRPC

private let logger = Logger(subsystem: "net.jvacek.TransmissionSwift", category: "core")

public actor RPCTorrentService: TorrentService {
    private let client: any TransmissionClient
    private let pollingInterval: @Sendable () -> TimeInterval
    private var continuation: AsyncStream<[Torrent]>.Continuation?
    private var pollTask: Task<Void, Never>?

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

    public func torrentsStream() async -> AsyncStream<[Torrent]> {
        // Unicast: cancel any existing poll loop before handing back a new stream.
        pollTask?.cancel()
        let (stream, cont) = AsyncStream<[Torrent]>.makeStream()
        self.continuation = cont
        let task = Task { await self.runPollLoop() }
        self.pollTask = task
        // Cancelling the consumer's for-await must cancel the unstructured poll task.
        cont.onTermination = { [task] _ in task.cancel() }
        return stream
    }

    public nonisolated var supportsActions: Bool { false }

    public func freeSpace() async -> Int64? {
        try? await client.sessionGet().downloadDirFreeSpace
    }

    public func torrents() async throws -> [Torrent] {
        let resp = try await client.torrentGet(fields: TorrentGetResponse.listFields, ids: nil)
        return resp.torrents.map { Torrent(wire: $0) }
    }

    private func runPollLoop() async {
        while !Task.isCancelled {
            do {
                continuation?.yield(try await torrents())
            } catch {
                logger.error("Poll error: \(error)")
            }
            try? await Task.sleep(for: .seconds(max(1, pollingInterval())))
        }
        continuation?.finish()
    }

    // MARK: - Stubs (wired in 7b)

    private var notImplemented: TransmissionError {
        .serverError("action methods not yet wired")
    }

    public func start(_ ids: [Torrent.ID]) async throws { throw notImplemented }
    public func stop(_ ids: [Torrent.ID]) async throws { throw notImplemented }
    public func remove(_ ids: [Torrent.ID], deleteLocalData: Bool) async throws {
        throw notImplemented
    }
    public func verify(_ ids: [Torrent.ID]) async throws { throw notImplemented }
    public func setFilesWanted(_ id: Torrent.ID, fileIDs: [TorrentFile.ID], wanted: Bool)
        async throws
    {
        throw notImplemented
    }
    public func setFilePriority(
        _ id: Torrent.ID, fileIDs: [TorrentFile.ID], priority: TorrentPriority
    ) async throws {
        throw notImplemented
    }
    public func setOptions(_ id: Torrent.ID, options: TorrentOptions) async throws {
        throw notImplemented
    }
    public func setAlternativeSpeedEnabled(_ enabled: Bool) async throws { throw notImplemented }
    public func isAlternativeSpeedEnabled() async -> Bool { false }
    public func add(
        fileURL: URL?,
        magnetURL: String?,
        destination: String,
        label: String?,
        priority: TorrentPriority,
        startWhenAdded: Bool
    ) async throws {
        throw notImplemented
    }
}
