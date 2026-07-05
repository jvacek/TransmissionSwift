# Slice 7a — Code Review

Reviewed commits `ed4f1b1`, `2645505`, `5fc28fc` (TorrentMapping + RPCTorrentService, app wiring, action-button gating).

## Findings

### Correctness

**1. Silent no-op when `profile.rpcURL` is nil** (`ContentView.swift:connectToProfile`)
```swift
guard let rpcURL = profile.rpcURL else { return }
```
If a saved profile has an unparseable URL the guard returns silently, leaving `TorrentStore.connection` stuck at `.connecting`. The user sees an infinite spinner with no explanation. Should instead call `store.connect(service:)` with a service that immediately yields a disconnection, or at minimum set `store.connection = .disconnected(reason: "Invalid server URL")` before returning.

**2. Two RPC calls per poll cycle** (`TorrentStore.startStream` + `RPCTorrentService.freeSpace`)
```swift
for await snapshot in stream {
    self.torrents = snapshot
    self.freeSpace = await self.service.freeSpace()  // ← second round-trip
```
Every 5-second tick makes a `torrentGet` and then a `sessionGet`. Both are small, but on a slow/proxied connection this doubles latency and request count. Options: (a) add `"download-dir-free-space"` to the existing `session-get` call (already in `SessionInfo` — just request it on every tick), or (b) fetch it once at connect time and only refresh on a longer cadence. Not urgent, but worth addressing before 7b.

**3. Stream-cancellation test doesn't verify the loop actually stops** (`TorrentMappingTests.swift`, `RPCTorrentServiceTests`)
```swift
_ = iterator  // silence unused warning; ARC releases it when this scope exits
```
The test confirms the loop *started* (callCount ≥ 1) but never asserts it *stopped* after the iterator is dropped. With `pollingInterval: { 60 }`, you can't wait for a second call, but you could verify `task.isCancelled` on the stored `pollTask` or add a `didStop` hook. As-is, the test would pass even if `onTermination` was wired incorrectly. Low priority — the logic is correct — but the test is incomplete.

**4. `errorMessage` is nil when `error >= 2` but `errorString` is empty**
```swift
let errorMessage: String? = (wire.error >= 2 && !wire.errorString.isEmpty) ? wire.errorString : nil
```
Status will be `.error` (correct) but `errorMessage` will be `nil`, so the inspector's General tab shows the error state dot with no explanation text. Should fall back to a generic string (e.g. `"Error \(wire.error)"`) when `errorString` is empty and `error >= 2`.

### Minor / Polish

**5. `mapStatus` visibility** — marked `internal` (no modifier = package-internal), accessed from `@testable import` in tests. The plan called for `private`, but `internal` is deliberate here to enable direct table testing. Fine as-is; no change needed.

**6. ETA == 0 maps to nil** — `wire.eta > 0` excludes zero. An ETA of 0 (imminently completing) becomes nil in the UI. Acceptable; it's transient and practically invisible. The test documents the choice explicitly. OK.

**7. `actionsEnabled` in the context menu vs. inspector tabs** — toolbar and list context menu are gated, but the inspector's Options tab (`setOptions`) and Files tab checkboxes/priority pickers are not. In mock mode this doesn't matter. In 7b once stubs are replaced, ensure those tabs check `actionsEnabled` or simply stop being disabled wholesale.

### What's correct and well-done

- Status mapping table (error ≥ 2, isFinished, 0–6) — exactly matches the plan.
- Ceiling division for `havePieces` — correct.
- `sitename` optional with URL fallback — correct.
- `onTermination { [task] _ in task.cancel() }` — correct capture, prevents orphaned poll loop.
- `TorrentStore.connect(service:)` with state reset — clean server-switching hook.
- Real `Test Connection` wired in `ServerProfileForm` — good bonus over the stub.
- Free space shown conditionally when non-nil — correct (hidden during `.connecting`).
- `supportsActions` protocol default `true` keeps MockTorrentService unchanged.

## Summary

Three things worth fixing before the next slice: (1) the silent failure on invalid URL, (2) the double RPC call per tick, (3) the empty `errorMessage` fallback. Stream test incompleteness is low priority. Everything else is solid.
