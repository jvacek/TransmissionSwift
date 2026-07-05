# Slice 7a — Torrent List via Real RPC

## Context

Slices 0–6 are complete: the full UI shell runs against `MockTorrentService` with fixture data. This plan wires the real RPC layer — scoped to the minimum slice that gets a live torrent list refreshing every N seconds (configurable). Action methods (`start`, `stop`, `remove`, etc.) and inspector-level data (per-file, per-peer, tracker stats) are left as stubs for later sub-slices.

---

## Known "surprises" vs. the mock assumptions

These are places where the wire protocol diverges from what the mock implies:

1. **No `.error` or `.completed` RPC status.** The wire `status` field is an integer 0–6. `.error` is signalled by a *separate* `error: Int` field whose values are `tr_stat` error types: 0 = OK, 1 = tracker **warning**, 2 = tracker error, 3 = local error. Only ≥ 2 maps to `.error` — a tracker warning is benign and keeps the normal status (matches transgui and the official web UI). `.completed` comes from the boolean `isFinished`; per `transmission.h`, *"only paused torrents can be finished"*, so a finished torrent always has `status == 0` — never gate `.completed` on status 6. Mapping (first match wins):
   ```
   error >= 2     → .error      (tracker/local error, overrides status)
   isFinished     → .completed  (co-occurs only with status 0)
   0              → .paused
   1 / 3 / 5      → .queued
   2              → .checking
   4              → .downloading
   6              → .seeding
   ```

2. **ETA sentinels.** Wire uses `-1` (`TR_ETA_NOT_AVAIL`) and `-2` (`TR_ETA_UNKNOWN`) — both map to `nil`. Domain `.infinity` (used by the mock for idle-seeding) doesn't come from the wire; keep it absent in the RPC mapping and let the UI treat `nil` eta on a seeding torrent as "no limit".

3. **Torrent-get fields are camelCase; session-get fields are kebab-case.** `SessionInfo.swift` already shows the kebab pattern for session fields. Torrent fields (`rateDownload`, `totalSize`, `downloadDir`, `hashString`, etc.) are camelCase — no custom `CodingKeys` needed on `WireTorrent` for most fields. Confirm against the live daemon before finalising field names.

4. **`trackers` vs `trackerStats` duality.** `trackers` is the static announce URL list; `trackerStats` is the live state (seeder count, last-announce result). The domain `Tracker` type combines both. For 7a, include `trackers` only (to get `primaryTracker`) and leave `trackerStats` for the inspector slice. Set `seedCount` to `0` for now. Note `trackers.sitename` was only added in Transmission 4.0.0 (rpc-version 17) — decode as `String?` and fall back to parsing the host from `announce`, so a 3.x daemon doesn't fail the whole response decode.

5. **`haveValid` is bytes, domain `havePieces` is count.** `haveValid` only counts fully-verified pieces, so ceiling division is exact — floor would show `pieceCount - 1` on a complete torrent whose last piece is short. Convert: `pieceSize > 0 ? Int((haveValid + pieceSize - 1) / pieceSize) : 0`.

6. **`peersFrom` is a nested object with seven sub-fields.** Sum all to get `availablePeerCount` — but know it's an approximation: these counters bucket peers by discovery origin and their sum ≈ `peersConnected`, so "available" will roughly track "connected" in the list view. True swarm size is `trackerStats` seeder+leecher counts, which land in the inspector slice. Acceptable for 7a; verify against the live daemon.

7. **`queuePosition` of `-1` is not in the spec** — the spec documents positions as `[0...n)` only, so `-1` may never occur on a 4.x daemon. Keep the defensive `-1 → nil` mapping, but if the domain wants `nil` for "not waiting in a queue", derive that from status instead. Verify against the live daemon.

8. **`labels` absent on daemons < 3.00 (rpc-version 16).** Decode as `[String]?`; take `first` or `nil`. No version-gating needed in the domain layer — the `labels` field simply won't appear in older daemon responses and decodes as `nil`.

9. **`bandwidthPriority` is `-1/0/1`**, not the `0/1/2` the mock uses. Map: `-1 → .low`, `0 → .normal`, `1 → .high`.

---

## Files to create / modify

### A. `Packages/TransmissionRPC/Sources/TransmissionRPC/TorrentGet.swift` *(new)*

Wire types for `torrent-get`:

```swift
// Nested types
struct WirePeersFrom: Decodable {
    var fromCache, fromDht, fromIncoming, fromLpd, fromLtep, fromPex, fromTracker: Int
    var total: Int { fromCache + fromDht + fromIncoming + fromLpd + fromLtep + fromPex + fromTracker }
}

struct WireTrackerStub: Decodable {
    var announce: String
    var sitename: String?  // added in 4.0.0 (rpc-version 17); fall back to host parsed from announce
    var tier: Int
}

struct WireTorrent: Decodable {
    var id: Int
    var name: String
    var hashString: String
    var totalSize: Int64
    var status: Int
    var error: Int
    var errorString: String
    var isFinished: Bool
    var percentDone: Double
    var rateDownload: Int64
    var rateUpload: Int64
    var peersConnected: Int
    var peersSendingToUs: Int
    var peersGettingFromUs: Int
    var peersFrom: WirePeersFrom
    var eta: Int
    var uploadRatio: Double
    var downloadDir: String
    var addedDate: Int64
    var labels: [String]?
    var bandwidthPriority: Int
    var pieceCount: Int
    var pieceSize: Int64
    var haveValid: Int64
    var queuePosition: Int
    var trackers: [WireTrackerStub]?
}

struct TorrentGetArguments: Encodable {
    var fields: [String]
    var ids: [Int]?
}

struct TorrentGetResponse: Decodable {
    var torrents: [WireTorrent]
}

// The 26-field list used for the list view
extension TorrentGetResponse {
    static let listFields = [
        "id", "name", "hashString", "totalSize",
        "status", "error", "errorString", "isFinished",
        "percentDone", "rateDownload", "rateUpload",
        "peersConnected", "peersSendingToUs", "peersGettingFromUs", "peersFrom",
        "eta", "uploadRatio",
        "downloadDir", "addedDate",
        "labels", "bandwidthPriority",
        "pieceCount", "pieceSize", "haveValid",
        "queuePosition", "trackers",
    ]
}
```

### B. `Packages/TransmissionRPC/Sources/TransmissionRPC/TransmissionClient.swift` *(extend)*

Add to `TransmissionClient` protocol:
```swift
func torrentGet(fields: [String], ids: [Int]?) async throws(TransmissionError) -> TorrentGetResponse
```

### C. `Packages/TransmissionRPC/Sources/TransmissionRPC/URLSessionTransmissionClient.swift` *(extend)*

Implement `torrentGet` using the existing `send()` helper (same pattern as `sessionGet`).

### D. `Packages/TransmissionCore/Sources/TransmissionCore/TorrentMapping.swift` *(new)*

`extension Torrent { init(wire: WireTorrent) }` — encapsulates all the surprise logic above. Returns `Torrent` with empty `files: []`, `peers: []`, `trackers: []`, `seedCount: 0`, and default `options: TorrentOptions()` (all populated in later slices). Include a `private func mapStatus(_:error:isFinished:) -> TorrentStatus` helper so the logic is testable.

### E. `Packages/TransmissionCore/Sources/TransmissionCore/RPCTorrentService.swift` *(new)*

```swift
public actor RPCTorrentService: TorrentService {
    private let client: TransmissionClient
    private let pollingInterval: @Sendable () -> TimeInterval
    private var continuation: AsyncStream<[Torrent]>.Continuation?
    private var pollTask: Task<Void, Never>?

    public init(
        client: TransmissionClient,
        pollingInterval: @escaping @Sendable () -> TimeInterval = {
            UserDefaults.standard.double(forKey: "pollingIntervalSeconds")
        }
    ) { ... }

    public func torrentsStream() async -> AsyncStream<[Torrent]> {
        pollTask?.cancel()  // unicast, like the mock: a new subscriber replaces the old loop
        return AsyncStream { continuation in
            self.continuation = continuation
            let task = Task { await self.runPollLoop() }
            self.pollTask = task
            // Without this, cancelling the consumer's for-await would orphan the
            // poll loop — `Task.isCancelled` in an unstructured Task is never set
            // by anyone else.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func torrents() async throws -> [Torrent] {
        let resp = try await client.torrentGet(
            fields: TorrentGetResponse.listFields, ids: nil)
        return resp.torrents.map { Torrent(wire: $0) }
    }

    private func runPollLoop() async {
        while !Task.isCancelled {
            do {
                continuation?.yield(try await torrents())
            } catch {
                logger.error("Poll error: \(error)")
                // stay in loop; store remains in .connecting / .connected with stale data
            }
            try? await Task.sleep(for: .seconds(max(1, pollingInterval())))
        }
        continuation?.finish()
    }

    // ── Stubs for action methods (wired in 7b) ──────────────────────────────
    public func start(_ ids: [Torrent.ID]) async throws { throw notImplemented }
    public func stop(_ ids: [Torrent.ID]) async throws { throw notImplemented }
    // ... remaining stubs ...
    public func isAlternativeSpeedEnabled() async -> Bool { false }  // non-throwing — can't stub with a throw
    private var notImplemented: TransmissionError { .serverError("action methods not yet wired") }
}
```

Notes:
- The interval closure is read on each tick, so Preferences changes take effect on the *next* sleep with no restart. Injecting it (with the `UserDefaults` read as the default) keeps `TransmissionCore` decoupled from the app's pref key and lets tests pass a constant.
- `TransmissionCore` has no logger yet — add `import OSLog` and `private let logger = Logger(subsystem: "net.jvacek.TransmissionSwift", category: "core")` (same pattern as `URLSessionTransmissionClient`).
- `torrents()` is part of the `TorrentService` protocol and falls out of the poll loop for free — implement it for real, not as a stub.

### F. `Packages/TransmissionCore/Tests/TransmissionCoreTests/TorrentMappingTests.swift` *(new)*

Swift Testing suite covering the status mapping surprise cases:
- `error >= 2` → `.error` regardless of status integer
- `error == 1` (tracker warning) does **not** → `.error`; status maps normally
- `isFinished` (co-occurs with status 0) → `.completed`, not `.paused`
- All 7 status codes → correct domain cases
- ETA: -1, -2 → `nil`; positive → `TimeInterval`
- `queuePosition: -1` → `nil`
- `bandwidthPriority: -1` → `.low`
- `havePieces`: ceiling division — complete torrent with a short last piece → `pieceCount`, not `pieceCount - 1`
- missing `sitename` → tracker host falls back to parsing `announce`

Plus a small `RPCTorrentServiceTests` with a stub client: terminating the stream (consumer cancels its `for await`) stops the poll loop — no further `torrentGet` calls.

### G. `TransmissionSwift/PreferencesView.swift` *(update)*

Add to the **General** pane (after the download folder row):

```swift
@AppStorage("pollingIntervalSeconds") private var pollingInterval: Double = 5.0

LabeledContent("Refresh interval") {
    HStack {
        TextField("", value: $pollingInterval, format: .number)
            .frame(width: 52)
        Stepper("", value: $pollingInterval, in: 1...60, step: 1)
            .labelsHidden()
        Text("seconds")
            .foregroundStyle(.secondary)
    }
}
```

Register the default once in `TransmissionSwiftApp.init()`:
```swift
UserDefaults.standard.register(defaults: ["pollingIntervalSeconds": 5.0])
```

### H. `TransmissionSwift/TransmissionSwiftApp.swift` + `ContentView.swift` *(update)*

Boot path changes:
- `--mock-data` → `MockTorrentService` (unchanged)
- No profiles → `AddServerForm` (unchanged)
- Active profile exists, no `--mock-data` → build `URLSessionTransmissionClient` from profile credentials, wrap in `RPCTorrentService`, inject into environment as `TorrentStore`

**The active profile is not fixed at launch.** `TransmissionSwiftApp.init()` runs once, but the active profile can appear or change at runtime (first-run AddServerForm flow, later server switching) — so the service can't be chosen only in `init`. Plan:
- Give `TorrentStore` a `connect(service:)` method: cancel the current `streamTask`, reset to `.connecting`, swap the service, re-subscribe.
- In `ContentView`, react to the active profile (e.g. `.task(id: profileStore.activeProfile?.id)`): build client + `RPCTorrentService` for the new profile and call `store.connect(service:)`. The `--mock-data` path keeps injecting the mock at init and skips this.

`ContentView` currently shows `ServerStatusView` for the real-server path. With slice 7a in place, replace that branch with `MainWindow` (slice 6's connecting/disconnected states already handle the transition). `ServerStatusView.swift` can be deleted if it's now dead code.

---

## Out of scope for 7a

- Action methods (`start`, `stop`, `remove`, `verify`, `add`) — stubbed
- Inspector tabs with live data (files, peers, trackerStats)
- Alt-speed toggle wired
- Session-set wired to Preferences
- Background polling pause (`ScenePhase`)
- Disconnection state propagation (store stays in `.connecting` if first poll fails — visible as "Connecting…" spinner; acceptable v1 UX)
- Delta polling — `ids: "recently-active"` (whose response adds a `removed` array) plus `format: "table"` is how transgui/the web UI shrink steady-state polls. 7a replaces the full snapshot every tick; adopting deltas later changes the store's merge logic from "replace" to "patch + remove".

---

## Verification

1. `swift test --package-path Packages/TransmissionRPC` — existing tests + new decode test against a captured fixture
2. `swift test --package-path Packages/TransmissionCore` — existing 20 tests + new mapping tests (target: ~28 total)
3. `BuildProject` (Xcode MCP) — clean build
4. Run app without `--mock-data` against local daemon (`transmission-daemon -g ~/.transmission-dev …`); confirm torrent list populates and refreshes at the configured interval
5. Change polling interval in Preferences; confirm next refresh uses the new value
6. Opt-in E2E: `TEST_RUNNER_TRANSMISSION_E2E=1 xcodebuild test -scheme TransmissionSwift`
