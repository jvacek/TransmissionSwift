# Slice 7b onwards — Remaining RPC wiring

## Where we are

**7a fixes** ✅ — all three landed (invalid URL → `.disconnected`, double poll collapsed, `errorMessage` fallback with `"Error N"` when `errorString` is empty).

**7b** ✅ — Action methods fully wired. Key points:
- `TorrentActions.swift` with all wire request/response types (`TorrentIDArguments`, `TorrentRemoveArguments`, `TorrentSetArguments`, `TorrentAddArguments`/`TorrentAddResponse`/`WireTorrentAdded`, `SessionSetArguments`).
- `SessionInfo.altSpeedEnabled` added; `TransmissionError.torrentDuplicate(name:)` added.
- `TransmissionClient` extended with 5 new methods; `URLSessionTransmissionClient` implements them.
- `RPCTorrentService`: all stubs wired, `supportsActions` override removed (defaults to `true`), `SessionInfo` cached in `freeSpace()` for alt-speed state and rpc-version gating.
- `TorrentStore`: `ActionError` enum + `lastActionError`, `do/catch` replacing `try?`, initial `isAlternativeSpeedEnabled` sync after connect.
- `MainWindow`: `.alert(item:)` for `lastActionError`.
- Tests: 19 passing in `TransmissionRPC` (fixture decode + encode), 28 passing in `TransmissionCore`.

**7c** ✅ — Inspector live data fully wired. Key points:
- Optional `files`, `fileStats`, `peers`, `trackerStats` added to `WireTorrent`; `inspectorFields` field list on `TorrentGetResponse`.
- `TorrentFile.init(file:stat:index:)`, `Peer.init(wire:)`, `Tracker.init(stat:)` mapping extensions in `TorrentMapping.swift`; `Torrent.init(wire:)` uses them when fields are present.
- `TrackerState` mapping uses `hasAnnounced`/`lastAnnounceSucceeded`/`announceState` booleans (not `announceState` alone).
- `TorrentService.inspectorData(for:)` protocol method; `RPCTorrentService` fetches `listFields + inspectorFields` for a single ID; `MockTorrentService` returns from state.
- `TorrentStore.inspectorDetail: Torrent?` + `fetchInspectorDetail(for:)` — separate from the main list so poll ticks don't wipe it.
- `InspectorView` passes `inspectorDetail` to Files/Peers/Trackers tabs; triggers fetch via `.task(id: torrent.id)`.
- Tests: 70 passing in `TransmissionCore` (new suites: TorrentFile, Peer, Tracker mapping, inspector field integration).

---

## Slice 7b — Action methods

Wire the mutation half of `TorrentService` so `supportsActions` can become `true`.

### RPC additions (`TransmissionRPC`)

New file `TorrentActions.swift`:

```swift
// torrent-start / torrent-stop / torrent-verify / torrent-remove
struct TorrentIDArguments: Encodable { var ids: [Int] }
struct TorrentRemoveArguments: Encodable { var ids: [Int]; var deleteLocalData: Bool }

// torrent-set (files-wanted, files-unwanted, priority-high/normal/low, + all TorrentOptions fields)
struct TorrentSetArguments: Encodable { ... }   // only non-nil fields encoded

// torrent-add (filename or metainfo)
struct TorrentAddArguments: Encodable { ... }
struct TorrentAddResponse: Decodable {
    enum CodingKeys { ... }
    var torrentAdded: WireTorrentAdded?
    var torrentDuplicate: WireTorrentAdded?
}
struct WireTorrentAdded: Decodable { var id: Int; var name: String; var hashString: String }

// session-set (alt-speed-enabled only, for now)
struct SessionSetArguments: Encodable { var altSpeedEnabled: Bool? }
```

Wire-key gotchas (spec: `reference/rpc-spec-4.0.6.md`):

- **Key casing is mixed *within* the same RPC object.** `torrent-set` uses `files-wanted` (kebab) next to `downloadLimit`/`queuePosition` (camel); `torrent-add` similarly (`download-dir`, `peer-limit` vs `bandwidthPriority`); `torrent-remove` uses `delete-local-data`. Every Arguments type needs explicit `CodingKeys` — do **not** add a global `keyEncodingStrategy` to the client.
- **An empty array for `files-wanted` / `files-unwanted` / `priority-*` means "ALL files"** (spec §3.2). Never encode `[]` unless that's intended — synthesized `Encodable` already omits nil optionals, so model "not set" as `nil`, never `[]`.
- `torrent-add`: magnet links go through `filename` (it accepts a URL or magnet); only `.torrent` file contents use base64 `metainfo`. The `labels` arg requires RPC ≥ 17 (Transmission 4.0) — omit it on older daemons. `startWhenAdded` maps to the *inverted* `paused` flag; test the negation.

Extend `TransmissionClient`:
```swift
func torrentAction(_ method: String, ids: [Int]) async throws(TransmissionError)
func torrentRemove(ids: [Int], deleteLocalData: Bool) async throws(TransmissionError)
func torrentSet(_ args: TorrentSetArguments) async throws(TransmissionError)
func torrentAdd(_ args: TorrentAddArguments) async throws(TransmissionError) -> TorrentAddResponse
func sessionSet(_ args: SessionSetArguments) async throws(TransmissionError)
```

`torrentAction` can cover start/stop/verify with just the method name and IDs — avoids three nearly-identical protocol methods.

### RPCTorrentService wiring

Replace all `throw notImplemented` stubs:

- `start` / `stop` / `verify` → `client.torrentAction("torrent-start/stop/verify", ids: ids)`
- `remove` → `client.torrentRemove(ids:deleteLocalData:)`
- `setFilesWanted` + `setFilePriority` → `client.torrentSet(TorrentSetArguments(ids:filesWanted:filesUnwanted:priorityHigh:...))`. **Guard: early-return when `fileIDs` is empty** — passing it through would encode `[]` = "all files" (see wire-key gotchas above).
- `setOptions` → `client.torrentSet(TorrentSetArguments(ids:options:))`
- `setAlternativeSpeedEnabled` → `client.sessionSet(SessionSetArguments(altSpeedEnabled: enabled))`
- `isAlternativeSpeedEnabled` → `client.sessionGet().altSpeedEnabled` (add field to `SessionInfo`, wire key `alt-speed-enabled`). The protocol signature is non-throwing (`async -> Bool`); on RPC failure return the last known value (default `false`) rather than changing the protocol.
- `add` → `client.torrentAdd(TorrentAddArguments(...))`. The response carries only `id`/`name`/`hashString` — not enough to build a domain `Torrent`, so **don't insert a stub; just wait for the next poll** (invisible at 1–5 s intervals). Do surface `torrent-duplicate` to the user (the RPC result is still `"success"`, so without handling it a duplicate add silently looks like it worked).
- After wiring: remove `supportsActions: Bool { false }` override; the default `true` kicks in.

### Tests

`TransmissionRPCTests`: fixture-based decode tests for each new response type (capture from daemon: `torrent-start`, `torrent-add`, `torrent-set`). Encode tests for `TorrentSetArguments`: nil fields absent from the JSON, and **no `[]` ever emitted for the file-index keys**. Plus the `paused`/`startWhenAdded` negation.

---

## Slice 7c — Inspector live data

Wire the three tabs that need additional `torrent-get` fields: Files, Peers, Trackers.

### New fields in `TorrentGetResponse`

Add a second field list `TorrentGetResponse.inspectorFields` that requests:
- `files` — `[{name, length, bytesCompleted}]`
- `fileStats` — `[{bytesCompleted, wanted, priority}]`  (parallel array to `files`)
- `peers` — `[{address, clientName, flagStr, progress, rateToClient, rateToPeer}]`
- `trackerStats` — `[{id, tier, host, lastAnnounceResult, lastAnnounceTime, lastAnnounceSucceeded, hasAnnounced, announceState, seederCount, leecherCount, downloadCount, isBackup}]`

### New wire types

`WireFile`, `WireFileStat`, `WirePeer`, `WireTrackerStat` in `TorrentGet.swift`.

⚠️ `WireFileStat.wanted` must be `Int`, not `Bool` — the daemon serializes it as `0`/`1` for backwards compatibility (spec §3.3 note) and `JSONDecoder` won't coerce numbers to `Bool`. Capture a real `fileStats` fixture early to lock this in.

### Mapping extension

`extension TorrentFile { init(file: WireFile, stat: WireFileStat, index: Int) }` — `id` = array index (files have no wire ID; index is also what `files-wanted` takes)
`extension Peer { init(wire: WirePeer) }` — no GeoIP for now; `countryCode = nil`. Rate direction: `rateToClient` = bytes flowing *to us* → `downloadSpeed`; `rateToPeer` → `uploadSpeed`.
`extension Tracker { init(stat: WireTrackerStat) }` — builds `statusMessage` from `lastAnnounceResult`/`lastAnnounceTime`

### On-demand fetch

The inspector needs richer data than the list view. Options:

**A. One combined poll** — request both `listFields + inspectorFields` every tick. Simple; wastes bandwidth when inspector is closed.

**B. Two-tier polling** — list poll every N seconds; when inspector is visible, a separate one-shot fetch for the selected torrent's files/peers/trackerStats, triggered by selection change or a short sub-interval timer. Avoids fetching unused data.

Recommendation: **B**, because `peers` and `fileStats` can be very large (hundreds of entries per torrent). Gate the inspector fetch on `store.inspectorVisible && store.selectedTorrents.count > 0`. Implement as a separate `func inspectorData(for id: Torrent.ID) async throws -> Torrent` method on `TorrentService` (MockTorrentService just returns the fixture).

Two constraints option B must respect:

1. **The fetch must request `listFields + inspectorFields`** for the single id. A `Torrent` can't be built from inspector fields alone — the domain initializer needs status, progress, sizes, etc. Combined fields for one torrent is cheap and reuses the existing mapping.
2. **Don't merge inspector data into `store.torrents`** — the poll loop replaces that array wholesale every tick with list-fields-only data, so merged files/peers/trackers would be wiped on the next poll. Instead the store holds a separate `inspectorDetail: Torrent?` that the three inspector tabs read (they currently read `torrent.files` etc. off the listed torrent — repoint them).

### `TrackerState` mapping

Don't map from `announceState` alone — it describes the announce *machine*, not tracker health. A healthy tracker spends nearly all its time in state 1 (waiting between announces) and is only 3 (active) for the sub-second announce itself, so an `announceState`-only mapping shows everything as `.idle`. Use the booleans the spec provides instead:

```
hasAnnounced && !lastAnnounceSucceeded   → .error    (statusMessage from lastAnnounceResult)
lastAnnounceSucceeded || announceState == 3 → .working
otherwise (never announced, backup, queued) → .idle
```

(No string comparison against `lastAnnounceResult` — `lastAnnounceSucceeded: Bool` exists for exactly this. The 0–3 `announceState` values aren't enumerated in the RPC spec doc; they come from `tr_tracker_state` in transmission.h.)

---

## Slice 7d — Disconnection state propagation

Currently, the store stays in `.connecting` forever if the first poll fails, and stays `.connected` with stale data if subsequent polls fail. Neither surfaces an error to the user.

### Approach

Change `RPCTorrentService.torrentsStream()` to return `AsyncThrowingStream<[Torrent], Error>` and update `TorrentStore.startStream()` to catch:

```swift
do {
    for try await snapshot in stream {
        torrents = snapshot
        ...
    }
} catch {
    connection = .disconnected(reason: error.localizedDescription)
}
```

**Failure policy** — a thrown error ends the stream, so don't throw on the first failure or a single timeout (sleeping NAS, brief Wi-Fi blip) flips the UI to "Disconnected" and stops polling until the user clicks Reconnect. The current loop has the opposite problem (swallows everything). Policy: throw immediately on fatal errors (auth, invalid URL/host); for transient ones (timeout, connection refused) keep polling and only throw after **3 consecutive failures**. A successful poll resets the counter.

`MockTorrentService` returns an `AsyncThrowingStream` that never throws (trivial migration). The `TorrentService` protocol changes from `AsyncStream` to `AsyncThrowingStream`.

Alternative (less invasive): keep `AsyncStream<[Torrent]>` but add a companion `AsyncStream<String>` property `errorStream` to the protocol — the service emits error messages; the store subscribes separately. More complex; not recommended.

On disconnect, `MainWindow`'s slice 6 "Disconnected" state activates. The Reconnect button calls `store.connect(service: service)` (already exists) with the same service, resetting to `.connecting` and restarting the loop.

---

## Slice 7e — Background polling pause

When the app moves to the background, polling wastes battery/network. The plan doc specified `ScenePhase` as the mechanism.

### Implementation

In `ContentView` (or a new `MainWindow` modifier):
```swift
@Environment(\.scenePhase) private var phase
.onChange(of: phase) { _, new in
    if new == .background { torrentStore.pausePolling() }
    else if new == .active { torrentStore.resumePolling() }
}
```

`TorrentStore` exposes `pausePolling()` / `resumePolling()`. These forward to `RPCTorrentService` which suspends the poll loop (e.g., by checking an actor-isolated `isPaused` flag in the loop, or by cancelling and restarting the task). `resumePolling()` must trigger an immediate poll rather than waiting out the interval, or the UI shows stale data for up to N seconds after re-activation.

MockTorrentService: no-ops.

⚠️ **Verify `ScenePhase` behaves on macOS before building on it.** Its semantics differ from iOS: the phase commonly stays `.active`/`.inactive` while the app runs, `.background` is typically only reported when windows are closed/hidden, and closing the last window may tear down the scene so `onChange` never fires. First step of this slice: log phase transitions empirically. If `.background` never fires in practice, fall back to `NSApplication.didHide/didUnhideNotification` (acceptable — this code lives in the app target).

---

## Open items from `ui-buildout.md` (polish, not blocking)

- **Slice 3 follow-up:** "Choose…" directory picker for download destination in Add Torrent sheet. Needs `fileImporter(allowedContentTypes: [.folder])`.
- **Slice 4 follow-up:** Live stats subtitle in toolbar title menu (active count + speeds).
- **Session-set in Preferences:** Speed limit panes write to `@AppStorage` only; slice 7b can plumb them through `session-set` as part of the action-methods pass.
- **Sort order persistence:** `@AppStorage` for `sortOrder` in `TorrentListView`.
- **Labels sidebar gating:** Decide whether to hide the Labels section when `session.rpcVersion < 16` (Transmission < 3.00).
- **Status bar turtle button:** Keep or drop (same action as toolbar alt-speed toggle — decide once actions are wired).
- **Free space:** `SessionInfo.downloadDirFreeSpace` reads `download-dir-free-space`, which the 4.0.6 spec marks **DEPRECATED** in favor of the `free-space` method. Fine for now; migrate when touching session code.
- **Duplicate-add UX:** decide how the Add sheet surfaces `torrent-duplicate` (toast? select the existing torrent?).

---

## Suggested order

| Slice | Scope | Prerequisite |
|-------|-------|-------------|
| 7a fixes | Invalid URL, double poll, errorMessage | — |
| 7b | Action methods | 7a |
| 7c | Inspector live data | 7b (or parallel with 7b) |
| 7d | Disconnection propagation | 7b |
| 7e | Background pause | 7d |
| Polish | Sort persist, session-set in prefs, turtle button | 7b |
