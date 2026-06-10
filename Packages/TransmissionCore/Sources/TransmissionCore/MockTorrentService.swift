import Foundation

/// In-memory `TorrentService` backed by `MockFixtures`. Mutations advance the
/// state immediately and broadcast to subscribers. Optionally runs a 1-second
/// "tick" that advances downloading torrents toward completion so the UI looks
/// live.
///
/// Used by the `--mock-data` launch path and by SwiftUI previews. Tests
/// instantiate it directly and choose whether to `startTicking()`.
public actor MockTorrentService: TorrentService {
    private var state: [Torrent]
    private var continuation: AsyncStream<[Torrent]>.Continuation?
    private var altSpeed = false
    private var tickTask: Task<Void, Never>?

    public init(initial: [Torrent] = MockFixtures.torrents()) {
        self.state = initial
    }

    /// Begin a 1-second loop that advances progress on downloading torrents.
    /// Idempotent. Tests typically skip this for deterministic snapshots.
    public func startTicking() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self?.tick()
            }
        }
    }

    public func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    /// Advance time by one second. Public so tests can drive the simulation
    /// deterministically.
    public func tick() {
        for index in state.indices {
            advanceDownloadingTorrent(at: index)
        }
        broadcast()
    }

    private func advanceDownloadingTorrent(at index: Int) {
        guard state[index].status == .downloading,
            state[index].downloadSpeed > 0,
            state[index].progress < 1
        else { return }

        let delta = Double(state[index].downloadSpeed) / Double(state[index].size)
        let newProgress = min(1.0, state[index].progress + delta)
        state[index].progress = newProgress
        state[index].havePieces = Int(Double(state[index].pieces) * newProgress)
        if let eta = state[index].eta, eta != .infinity {
            state[index].eta = max(0, eta - 1)
        }
        if newProgress >= 1 {
            state[index].status = .seeding
            state[index].downloadSpeed = 0
            state[index].eta = .infinity
        }
    }

    private func broadcast() {
        continuation?.yield(state)
    }

    // MARK: - TorrentService

    public func torrents() async throws -> [Torrent] { state }

    public func torrentsStream() -> AsyncStream<[Torrent]> {
        let (stream, cont) = AsyncStream<[Torrent]>.makeStream()
        self.continuation = cont
        cont.yield(state)
        return stream
    }

    public func start(_ ids: [Torrent.ID]) async throws {
        let set = Set(ids)
        for index in state.indices where set.contains(state[index].id) {
            guard state[index].status == .paused || state[index].status == .queued else { continue }
            state[index].status = state[index].progress >= 1 ? .seeding : .downloading
        }
        broadcast()
    }

    public func stop(_ ids: [Torrent.ID]) async throws {
        let set = Set(ids)
        for index in state.indices where set.contains(state[index].id) {
            state[index].status = .paused
            state[index].downloadSpeed = 0
            state[index].uploadSpeed = 0
            state[index].eta = nil
        }
        broadcast()
    }

    public func remove(_ ids: [Torrent.ID], deleteLocalData: Bool) async throws {
        let set = Set(ids)
        state.removeAll { set.contains($0.id) }
        broadcast()
    }

    public func verify(_ ids: [Torrent.ID]) async throws {
        let set = Set(ids)
        for index in state.indices where set.contains(state[index].id) {
            state[index].status = .checking
            state[index].downloadSpeed = 0
            state[index].uploadSpeed = 0
        }
        broadcast()
    }

    public func setAlternativeSpeedEnabled(_ enabled: Bool) async throws {
        altSpeed = enabled
    }

    public func isAlternativeSpeedEnabled() async -> Bool { altSpeed }
}
