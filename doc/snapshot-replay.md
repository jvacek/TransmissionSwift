# Snapshot & Replay — reproduce real-server issues without the server

Status: **capture + replay implemented** (2026-08-21) — machinery, Developer
pane UI (Settings → Developer), and the `--snapshot <path>` replay launch path
are all in. Remaining: a no-daemon XCUITest and the AGENTS.md/reference cross-refs
(partially done in Slice C). No separate CLI binary.

## Problem

Bugs that only reproduce against Jonas's real daemon are hard to work on with an
AI agent:

- the agent can't reach the server (network, auth, credentials),
- real data can't be shared or committed (private-tracker passkeys, filenames,
  peer IPs),
- "works on my machine" applies to the *data*, not the code.

Goal: capture the daemon's state into a self-contained, anonymized snapshot file
**from inside the app**, and let the app (or tests) boot against it with a launch
flag — no daemon, no credentials, no extra binary, safe to attach to a bug report
or commit to the repo.

## Design in one paragraph

The app gains a **Developer pane in Settings** with a "Capture Snapshot…" button
(plus per-capture anonymization toggles). It pulls the full state from the
currently-connected daemon (`session-get` + `torrent-get` with the full field
list), deterministically redacts anything identifying (tracker URLs incl.
passkeys, peer IPs, names, paths, infohashes, timestamps), leak-checks the result
and refuses to write if anything survived, then saves one JSON file picked via
`NSSavePanel`. The app also gains a `--snapshot <path>` launch flag that boots a
`SnapshotTorrentService` — a third `TorrentService` implementation that decodes
the file through the **same wire→domain mapping as the live path**
(`Torrent(wire:)`) and serves a frozen view of the state.

## The seam: `TorrentService` (already exists)

The UI already depends on `protocol TorrentService`, never on RPC directly:

| Implementation | Used by |
|---|---|
| `MockTorrentService` | previews + empty no-server placeholder |
| `RPCTorrentService` | live daemon (slice 7) |
| **`SnapshotTorrentService` (new)** | `--snapshot <path>` — decodes the file, frozen, no network |

## Snapshot file format

One JSON file, stored **wire-shaped** — the `arguments` objects exactly as the
daemon shapes them:

```json
{
  "version": 1,
  "capturedAt": "2026-08-21T10:00:00Z",
  "source": { "daemonVersion": "4.1.2 (f234716f3e)", "rpcVersion": 19, "redacted": true },
  "session": { "version": "...", "rpc-version": 19, "download-dir": "/fake/downloads", "...": "..." },
  "torrents": [ { "id": 1, "name": "Fuzzed Name 01", "downloadDir": "/fake", "...": "..." } ]
}
```

Why wire-shaped rather than domain-shaped:

- The load path decodes into the existing `WireTorrent` / `SessionInfo` types and
  maps via `Torrent(wire:)` — byte-identical code path to a live poll. If the
  mapping is buggy, the snapshot reproduces the bug.
- Decoding is tolerant of unknown fields (JSONDecoder ignores them), so a
  snapshot from a future daemon still loads.
- The redactor keys off JSON field names (suffix matching), so new daemon fields
  get sensible default treatment without code changes.

`source.host` is intentionally omitted — the capture host is itself identifying.

### Capture re-encodes decoded wire types

The app's RPC client decodes into typed structs and never exposes the raw
payloads. So capture re-encodes: `WireTorrent`, `WireFile`, `WireFileStat`,
`WirePeer`, `WirePeersFrom`, `WireTrackerStat`, `WireTrackerStub`, and
`SessionInfo` gain `Encodable` (their property names / CodingKeys already match
the daemon's key names, so the re-encoded JSON is the wire shape). Trade-off: any
daemon field the app doesn't decode is dropped — acceptable, since the app only
consumes what it decodes, and the bug-repro value is in the consumed fields.

## Redaction policy (deterministic, default on)

Every transform is seeded by the original value, so re-capturing the same state
produces the same file, and the same real tracker / IP / name always maps to the
same fake. Numbers, rates, sizes, ratios, counts, flags, and the daemon version
string pass through untouched — they're what reproducibility is about.

| Field class | Keys (suffix match) | Rule |
|---|---|---|
| Tracker URLs | `announce`, `scrape`, `host`, `blocklist-url` | Rewrite to `scheme://tracker-N.invalid/announce`. **Strip query and passkey-like path segments**; preserve scheme/port. Same host → same fake. Off with "Anonymize tracker names" (host kept, passkeys still stripped). |
| Tracker short names | `sitename` | Length-preserving fuzz (kept when tracker anonymization is off) |
| Peer addresses | `address` | IP → RFC 5737 range (IPv4) / `2001:db8::/32` (IPv6), deterministic per IP; port preserved |
| Torrent / file / label names | `name`; `files[].name`, `labels[]` | **Kept by default** so torrents stay identifiable; fuzz with "Include torrent names" off. Fuzzing keeps extensions, spaces, separators, and digit/letter class |
| Paths | `download-dir`, `incomplete-dir`, `downloadDir` | Fuzz path components, keep structure + extension |
| Infohash | `hashString` | Deterministic 40-hex fake |
| Free text | `errorString`, `lastAnnounceResult` | URLs, bare FQDNs, IPs, emails, and path tokens scrubbed (in that order); surrounding message text preserved |
| Timestamps | `addedDate`, `lastAnnounceTime`, `*Date`, `*Time` | Shift all by one offset (anchor: earliest `addedDate` → 2026-01-01). Everything shifts together, so "2h ago" style labels stay correct. |
| Everything else | — | Passthrough |

**Private-tracker passkeys are the #1 leak vector**: announce URLs carry a
per-user key (query param or a long path segment like `/announce/<user>/<key>`).
The `announce` rule strips them by construction, and the leak check is the
tripwire.

### Leak check (runs before writing; failure aborts)

Key-aware and option-aware: fields the redactor fully transforms (paths, hashes,
and — when opted out — names / tracker hosts) are skipped, since fuzzed
contents can legitimately look like arbitrary text (e.g. a fuzzed file name
`qwer.ty`). Kept names get an **IP check only** (no FQDN check — real names
contain dots). Kept tracker hosts are intentional, so only the passkey query
tripwire applies to them. Free text is checked for unscrubbed URLs (`://`),
non-doc IPs, `.onion`, and `?key=` remnants.

Scans the redacted JSON for anything that shouldn't survive:

- any IPv4 outside the RFC 5737 doc ranges + loopback
- any IPv6 outside `2001:db8::/32` + loopback
- any FQDN not ending in `.invalid` (and not `localhost`) — skipped when tracker
  anonymization is off
- `.onion` hostnames, `?key=`-style query params (never skipped — passkeys are
  non-negotiable)

Each detector gets unit tests with positive and negative cases.

### Output

The file is serialized with `.sortedKeys` + `.prettyPrinted`, so re-capturing the
same state produces a byte-identical, diffable file. The `SnapshotRedactionSummary`
is embedded as the `redactions` key (provenance for whoever reads the file), and
`source.redacted` flips to `true`. Numbers keep the daemon's JSON type (integers
stay integers) so the file decodes exactly like a live poll.

## Capture: in-app, Settings → Developer ✅

A **Developer** pane (7th tab, `wrench.and.screwdriver` icon) with
"Snapshots" + "Scope" + "Anonymization" sections:

- **Scope** (what gets captured): "Only capture torrents visible with current
  filters" (default on — the main window's filters/search/sort define the set)
  and "Limit torrent count" (default on, 10; stepper 1–500). The limit applies
  after filtering, in the currently-visible sort order, so the default capture
  is the 10 torrents you're looking at.
- **Anonymization** (defaults favor identifiable, focused captures; reset each
  launch): "Include torrent names" (default on), "Anonymize tracker names"
  (default on — off keeps hosts/sitenames real but passkeys are always
  stripped), "Include infohashes" (default off), "Preserve timestamps"
  (default off).
- **"Capture Snapshot…"** button → `NSSavePanel` (default name
  `snapshot-<date>.json`) → capture → result alert:
  "Captured N of M torrents … Redacted M tracker URLs (K passkeys), J peer IPs;
  timestamps shifted." — or an error alert. Disabled until the store reports
  `.connected`.

Mechanics (all in `TransmissionCore` so it's unit-testable without the UI):

- `TorrentService.captureRawSnapshot() async throws -> SnapshotFile` —
  protocol method with a default that throws "not supported"; only
  `RPCTorrentService` overrides it (one `torrentGet` with
  `listFields + inspectorFields` + one `sessionGet`, re-encoded).
- Scope: `SnapshotScope.apply(to:visibleOrder:maxTorrents:)` slices the raw
  torrents to the currently-visible ids (in sort order) and caps the count.
- `SnapshotFile` (unredacted envelope) → `SnapshotRedactor` (returns
  the redacted tree + a `SnapshotRedactionSummary` with the counts for the alert) →
  `SnapshotLeakChecker` (throws on any leak) → write file.
- `TorrentStore.captureSnapshot(to:options:)` orchestrates the pipeline and
  returns a `SnapshotCaptureResult` (summary + captured torrent count), so the
  Developer pane is a thin view calling one store action (and the whole pipeline
  is unit-testable with a stub service).

The `Settings` scene gains `.environment(torrentStore)` (it only has
`profileStore` + `faviconStore` today). In mock or snapshot-replay mode the
button surfaces the "not supported" error — capture is a live-connection feature.

## Replay in the app

Launch flag: `--snapshot <path>`, parsed in `TransmissionSwiftApp.init`
alongside `--ephemeral-profiles`:

- Boots `SnapshotTorrentService(fileURL:)` into the existing `TorrentStore`.
- Seeds a synthetic in-memory `ServerProfile` ("Snapshot — <filename>") so the
  toolbar title menu / status bar have something sensible; never persisted.
- Routes to `MainWindow` like mock mode does.

`SnapshotTorrentService` (new file in TransmissionCore):

- decodes the envelope → `[WireTorrent]` + `SessionInfo`
- maps with `Torrent(wire:)` — the exact function `RPCTorrentService.torrents()`
  uses
- `torrentsStream()` yields the list once and stays open (frozen: no tick, no
  poll loop)
- `freeSpace()` / `downloadDirectory()` / `isAlternativeSpeedEnabled()` answer
  from the stored session
- `supportsActions == false` — read-only replay. Mutating a point-in-time record
  makes no sense; the UI already knows how to disable actions.

## What this unlocks

1. **Agent repro without server access** — hit the bug, Settings → Developer →
   Capture Snapshot, attach the file to the bug report; the agent runs the app
   or tests against it.
2. **Safe to share by construction** — the genuinely traceable bits (passkeys,
   peer IPs, paths, timestamps) are scrubbed by default and the passkey/IP
   stripping is never optional; the leak-check tripwire refuses the file if
   anything survives. Names are opt-out so you can point at specific torrents.
3. **No-daemon UI tests** — today `TEST_RUNNER_TRANSMISSION_E2E=1` needs a live
   daemon; a snapshot-backed XCUITest runs anywhere, including CI.
4. **Committable regression fixtures** — capture an edge-case state once, keep it
   in the repo, reference it from unit + UI tests.

## Plan

### Slice A — capture machinery (TransmissionCore + TransmissionRPC) ✅

- [x] `Encodable` on the wire types (`WireTorrent` + inspector types, `SessionInfo`).
- [x] `SnapshotFile` / `SnapshotSourceInfo` / `SnapshotRedactionSummary` envelopes
      (`Snapshot.swift`), `SnapshotRedactor.swift`, `SnapshotLeakChecker.swift`.
- [x] `TorrentService.captureRawSnapshot()` (+ `RPCTorrentService` impl) and
      `TorrentStore.captureSnapshot(to:options:)` orchestration.
- [x] Tests: 3 new suites in TransmissionCore (redactor rules, leak detectors,
      pipeline/file verification) + wire re-encode shape in TransmissionRPC.

**Validation:** 125 core tests + 21 RPC tests pass, `swift format lint --strict`
clean. The fixture-based pipeline tests cover the full loop — redact → leak-check
→ write → read back → domain-map — with byte-determinism asserted. Real-daemon
capture wasn't run (no `transmission-daemon` on PATH); worth doing once the local
dev daemon is up (recipe in AGENTS.md).

### Slice B — UI + replay

Capture UI landed (2026-08-21): `DeveloperPrefsPane` (7th Settings tab,
save panel, result/error alerts), `.environment(torrentStore)` on the Settings
scene, button disabled until connected. Replay landed same day:

- `SnapshotTorrentService` (TransmissionCore): decodes the envelope via the
  same `SessionInfo` / `WireTorrent` / `Torrent(wire:)` path as a live poll,
  yields the list once (frozen, no tick), answers `freeSpace` /
  `downloadDirectory` / `isAlternativeSpeedEnabled` from the stored session,
  `supportsActions == false`. Mutations throw `SnapshotError.replayReadOnly`.
- `--snapshot <path>` (also `--snapshot=<path>`) in `TransmissionSwiftApp.init`:
  forces ephemeral profiles, seeds a synthetic in-memory `ServerProfile`
  ("Snapshot — <filename>") so the toolbar title /
  status bar have a label, and boots `SnapshotTorrentService` into the store.
  `ContentView` routes to `MainWindow` like mock mode but skips the connect task.
  If the file fails to decode, it logs "Snapshot load failed" and falls back to
  the empty mock.
- **Sandbox gotcha:** a sandboxed app cannot read an arbitrary path passed on the
  command line. Snapshot files live in `~/Downloads`, so the target gained
  `ENABLE_FILE_ACCESS_DOWNLOADS_FOLDER = readonly` (the `com.apple.security.files.downloads.read-only`
  entitlement). Read-only suffices — replay never writes.
- Tests: `SnapshotTorrentServiceTests` (7 tests: serve → map → session fields →
  frozen stream → read-only → inspector → unknown-version rejection).

**Validation:** 145 core tests + 21 RPC tests pass, `swift format lint --strict`
clean, app builds. Replay verified end-to-end against a real capture
(`~/Downloads/snapshot-2026-08-21-182355.json`, 10 torrents) launched with
`--snapshot`.

### Slice C — docs ✅

- Result notes in this doc (Slice B validation above), an AGENTS.md dev-tools
  line (with the `--snapshot` invocation + `ENABLE_FILE_ACCESS_DOWNLOADS_FOLDER`
  note), and a cross-ref from `reference/README.md`.
- **Remaining:** a no-daemon XCUITest launching `--snapshot <fixture>`
  (fixture located via `#filePath`-derived paths — no resource bundling).

Per Jonas's cross-stack preference, the validation loop closes early: capture a
snapshot from the local dev daemon at the end of slice A, boot the app on it
during slice B — end-to-end without ever touching the real server. Done: a real
`~/Downloads` capture (10 torrents) was replayed via `--snapshot`.

## Open questions

- **No-daemon XCUITest.** The one unimplemented piece: a UI test that boots
  `--snapshot <fixture>` and asserts the torrent list renders. Needs a small
  committed fixture (an anonymized capture, or a hand-trimmed one) referenced
  via `#filePath` — no resource bundling. The `--mock-data` launch flag was
  removed (superseded by `--snapshot`); `MockTorrentService` remains for
  previews and unit tests.
- **Headless capture.** An optional `--snapshot-capture --out <path>` launch arg
  (same pipeline, active saved profile, then exit) would let scripts / agents
  capture without touching the GUI — distributed with the app for free, no
  separate binary. Keychain access from a headless run may prompt; defer until
  there's a real need.
- **Replay actions.** Currently read-only. Mutating an in-memory copy (discarded
  on quit) is a natural later extension for exercising action bugs.
- **`session-stats` (bandwidth history).** Not consumed by the UI today — skip.
- **Daemon-side load** (start `transmission-daemon` with a snapshot). Explicitly
  out of scope — the app is the thing with launch flags, and loading torrents
  into a real daemon is a different, much harder problem.
