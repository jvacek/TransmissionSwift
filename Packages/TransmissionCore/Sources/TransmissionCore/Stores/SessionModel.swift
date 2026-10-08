import Foundation
import Observation
import TransmissionRPC

/// The connected daemon's session-level state: speed/network/queue settings,
/// alternative (turtle) speed, free space, version, port-test result and
/// transfer stats — plus the reads and writes that produce them.
///
/// The coordinator binds the current service on connect (for user-initiated
/// reads/writes) and drives the poll loop with an explicitly captured service
/// via `load(from:)`/`poll(from:)`, so a cancelled poll can't write a freshly
/// connected server's state.
@MainActor
@Observable
public final class SessionModel {
    /// The daemon's session settings (speed limits, network, queue, seed
    /// ratio/idle). Nil until the first session poll, or when disconnected.
    public private(set) var settings: SessionSettings?
    /// Whether alternative (turtle) speed limits are enabled.
    public private(set) var isAlternativeSpeedEnabled = false
    /// Free space (bytes) on the daemon's download directory.
    public private(set) var freeSpace: Int64?
    /// The daemon's long version string (e.g. `"4.1.2 (f234716f3e)"`).
    public private(set) var daemonVersion: String?
    /// Current + lifetime transfer statistics, fetched on demand.
    public private(set) var sessionStats: SessionStats?
    /// Result of the last `port-test`: nil = unknown, true/false = reachable.
    public private(set) var portIsOpen: Bool?
    /// Whether the daemon supports labels (rpc-version >= 17).
    public private(set) var supportsLabels = true

    /// Reports a user-facing action failure through the coordinator's shared
    /// alert channel. Set by `TorrentStore`.
    var onError: ((ActionError) -> Void)?

    private var reading: (any TorrentReading)?
    private var mutations: (any TorrentMutating)?

    public init() {}

    // MARK: - Binding to the current connection

    func connect(reading: any TorrentReading, mutations: (any TorrentMutating)?) {
        self.reading = reading
        self.mutations = mutations
    }

    /// Clear everything for a fresh connection.
    func reset() {
        settings = nil
        isAlternativeSpeedEnabled = false
        freeSpace = nil
        daemonVersion = nil
        sessionStats = nil
        portIsOpen = nil
        supportsLabels = true
    }

    // MARK: - Loads

    /// Initial load after connect: everything the session panes render, from
    /// the given (captured) service. `freeSpace()` also warms the RPC service's
    /// cached session, so it must run before the cache-backed reads.
    func load(from reading: any TorrentReading) async {
        freeSpace = await reading.freeSpace()
        daemonVersion = await reading.daemonVersion()
        settings = await reading.sessionSettings()
        isAlternativeSpeedEnabled = await reading.isAlternativeSpeedEnabled()
        supportsLabels = await reading.supportsLabels()
    }

    /// Periodic refresh (the free-space poll). Does not re-read alt-speed — a
    /// user toggle owns that until the next connect.
    func poll(from reading: any TorrentReading) async {
        freeSpace = await reading.freeSpace()
        daemonVersion = await reading.daemonVersion()
        supportsLabels = await reading.supportsLabels()
        settings = await reading.sessionSettings()
    }

    /// Refresh free space only (called after a post-mutation refresh elsewhere).
    public func refreshFreeSpace() async {
        guard let reading else { return }
        freeSpace = await reading.freeSpace()
    }

    /// Fetch current + lifetime transfer stats for the status-bar popover.
    /// Keeps stale values on failure — a failed refresh just shows old numbers.
    public func refreshSessionStats() async {
        guard let reading, let stats = await reading.sessionStats() else { return }
        sessionStats = stats
    }

    // MARK: - Actions

    /// Ask the daemon whether its peer port is reachable. Surfaces a failure
    /// when the service can't answer.
    public func testPort() async {
        guard let reading else { return }
        guard let result = await reading.isPortOpen() else {
            onError?(.failed(message: "The connected server couldn't report its port status."))
            return
        }
        portIsOpen = result
    }

    public func toggleAlternativeSpeed() async {
        guard let mutations else { return }
        let newValue = !isAlternativeSpeedEnabled
        do {
            try await mutations.setAlternativeSpeedEnabled(newValue)
            isAlternativeSpeedEnabled = newValue
            settings?.altSpeedEnabled = newValue
        } catch {
            onError?(ActionError.from(error))
        }
    }

    /// Apply a session-side setting change. `mutate` mutates a copy of the
    /// current `SessionSettings`; the patch carries only the changed fields,
    /// applied optimistically and rolled back / re-read on failure. No-ops
    /// without a live session.
    public func updateSessionSettings(_ mutate: (inout SessionSettings) -> Void) async {
        guard let mutations, let reading, var current = settings else { return }
        let before = current
        mutate(&current)
        guard current != before else { return }
        let patch = SessionSettingsPatch(before: before, updated: current)
        settings = current
        isAlternativeSpeedEnabled = current.altSpeedEnabled
        do {
            try await mutations.applySessionSettings(patch)
            settings = await reading.sessionSettings() ?? current
            isAlternativeSpeedEnabled = settings?.altSpeedEnabled ?? current.altSpeedEnabled
        } catch {
            onError?(ActionError.from(error))
            settings = await reading.sessionSettings() ?? before
            isAlternativeSpeedEnabled = settings?.altSpeedEnabled ?? before.altSpeedEnabled
        }
    }
}
