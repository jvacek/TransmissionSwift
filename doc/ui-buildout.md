# UI buildout — Mock-first slice

**Goal:** stand up all five screens from the Claude Design handoff (`reference/design_handoff_transmission_swift/`) against an in-memory mock service, then swap in the real RPC layer once the shell works end-to-end.

**Why mock-first.** Today the RPC layer only knows `session-get`. The design needs `torrent-get` with ~25 fields, `torrent-add`, `torrent-set`, `torrent-start/stop/remove`, `session-set`, `free-space`, plus a fan-out of derived state (filter facets, file/peer/tracker views). Building UI against a `MockTorrentService` means we can ship the entire UI surface — and exercise it with UI tests — before touching the wire protocol. The "wire real RPC" phase at the end is then contained to one package (`TransmissionCore` + `TransmissionRPC`) and leaves the views untouched.

**Platform reminder.** Per `ARCHITECTURE.md` we target **min macOS 26 only**. The design handoff hedged with macOS 14+ fallbacks; we don't need them. Use Liquid Glass APIs unconditionally (`.glassEffect`, `.glassProminent`, `ToolbarSpacer`, `.inspector`, `ContentUnavailableView`, `.searchable`, etc.) — no `if #available` guards.

---

## Strategy

### Mock at the service layer, not the RPC layer
We could mock `TransmissionClient` (the RPC protocol) and inject fakes. We won't, because:
- The UI doesn't think in RPC envelopes — it thinks in domain types (Torrent, File, Peer, Tracker, FilterFacets).
- Mirrors how `session-get` → `SessionInfo` → `ConnectionService` already layers today.
- The "wire real RPC" slice at the end becomes additive: define the RPC requests, map wire→domain, swap the service backing. Views don't move.

So the abstraction the views consume is `protocol TorrentService` in `TransmissionCore`, with two implementations:
- `MockTorrentService` — backed by the ported `data.jsx` fixtures, plus a `Task` that nudges progress/speeds every 1s to feel live.
- `RPCTorrentService` (later) — wraps a `TransmissionClient`, polls per `ARCHITECTURE.md` §5.

A launch flag — `--mock-data`, paralleling the existing `--ephemeral-profiles` — selects the mock at `TransmissionSwiftApp.init()`. This keeps the swap mechanical and lets every UI test run against deterministic data.

### Domain types live in `TransmissionCore`
Port the JS data model 1:1:
- `Torrent` (id, name, size, status, progress, down, up, peers, peersOf, seeds, eta, ratio, tracker, folder, added, label?, priority, pieces, pieceSize, have, queue?, errorMsg?)
- `TorrentStatus` enum: `.downloading .seeding .paused .checking .queued .error .completed`
- `TorrentFile`, `Peer`, `Tracker`, `FilterFacets` (status counts + per-tracker/folder/label rollups derived from `[Torrent]`)
- Every type gets a `static var sample`/`samples` for previews (taken from `data.jsx`).

### Observability
A single `@Observable` `TorrentStore` in `TransmissionCore` owns:
- `torrents: [Torrent]`
- `derived: FilterFacets` (recomputed when torrents change)
- `connection: ConnectionState` (`.connecting / .connected / .disconnected(error)`)
- `selectedFilter: SidebarFilter`, `selectedTorrentIDs: Set<Torrent.ID>`
- Polling task lifecycle

Views read `store` from the environment. View models stay minimal — `@Observable` + `@State`.

---

## Liquid Glass / HIG checklist (enforced per slice)

- **Toolbars:** items grouped by purpose with `ToolbarSpacer(.fixed)` separators; `ToolbarSpacer(.flexible)` to right-align trailing groups. `.toolbar(role: .editor)` where appropriate. Every icon-only button gets an `accessibilityLabel`.
- **Color discipline:** monochrome by default. Color is reserved for status (download blue / seed green / paused gray / checking orange / error red) and *one* primary CTA per surface (`.buttonStyle(.glassProminent)` on Add Torrent, Connect, Reconnect).
- **Materials:** never set custom backgrounds on `NavigationSplitView`, `Toolbar`, `Inspector`, `Sheet`, `Settings`. Status bar uses `.background(.regularMaterial)` only (no glass on content-layer surfaces — that's an LG anti-pattern).
- **Typography:** system font; numeric columns use `.monospacedDigit()`; paths/hashes/IPs/flags use `.monospaced()`; section headers title-style (not ALLCAPS).
- **Selection & focus:** standard `List(selection:)` and `Table(selection:)` — let the system render selection. No custom hover/selection chrome.
- **macOS chrome:** `WindowStyle.titleBar` (default). `.windowToolbarStyle(.unified)` for the main window. Single `Settings { … }` scene for prefs.
- **Menu bar commands:** wire File → Add Torrent…, Edit → Find (focuses search), View → Show Inspector via `.commands { CommandGroup(…) }`. Standard ⌘N / ⌘F / ⌘I.
- **Keyboard:** space toggles pause on selection, delete removes (with confirmation), ⌘R reconnects, ⌘⇧S manages servers.
- **Drag & drop:** `.dropDestination(for: URL.self)` on the root accepts `.torrent` files and magnet URLs → opens S2 prefilled.
- **Accessibility:** every status dot is a `Label` with text, hidden visually but exposed to VoiceOver.
- **Reduce transparency / motion:** verified by running the app with Accessibility settings flipped — system handles it as long as we don't hand-roll materials.

---

## Slices

Each slice is one PR-sized chunk. Tick boxes track progress.

### Slice 0 — Foundation (TransmissionCore) ✅

- [x] Domain types in `TransmissionCore`: `Torrent`, `TorrentStatus`, `TorrentPriority`, `TorrentFile`, `Peer`, `Tracker`, `TrackerState`, `SidebarFilter`, `TorrentStatusFilter`, `FilterFacets`, `FacetEntry`, `ConnectionState`, `InspectorTab`. All `Sendable`.
- [x] `MockFixtures.swift` — 10 torrents, full files/peers/trackers on the Debian fixture (id 5), stubs on the rest. Sample accessors as `Torrent.sample` / `Torrent.samples`, `ServerProfile.sample(s)`.
- [x] `protocol TorrentService: Sendable` — scope reduced to what slices 0–2 need: `torrents()`, `torrentsStream()`, `start/stop/remove/verify`, `setAlternativeSpeedEnabled` / `isAlternativeSpeedEnabled`. Add-torrent and per-file/priority mutations deferred to slices 3 (Add sheet) and 2 (Files tab).
- [x] `MockTorrentService` actor: fixtures + `startTicking()` (1s loop, deterministic — tests can call `tick()` directly). `start/stop/remove/verify` mutate state and broadcast via a stored `AsyncStream` continuation.
- [x] `@MainActor @Observable TorrentStore` — owns `torrents` (mirrored from stream), `connection`, selection/search/filter/inspector state, derived `facets`/`visibleTorrents`/`selectedTorrents`. Cancels selection on remove.
- [x] 17 tests across 5 suites — facets, filtering, search, mock mutations, store mirroring via stream — all green.

**Validation:** `swift test --package-path Packages/TransmissionCore` and `swift format lint --strict` both clean; Xcode app target builds via `BuildProject`.

### Slice 1 — Main window shell, mock-data (S1) ✅

- [x] `--mock-data` launch arg in `TransmissionSwiftApp.init` constructs a `MockTorrentService` (auto-ticks) and a `TorrentStore`, then injects both into the environment. Without the flag the store is backed by an empty mock — real RPC arrives in slice 7.
- [x] `ContentView` dispatches: `--mock-data` → `MainWindow`; no profile → `AddServerForm`; existing profile → `ServerStatusView` (unchanged single-profile path until slice 4 lands).
- [x] `MainWindow` = `NavigationSplitView { SidebarView } detail: { TorrentListView }`, with `.inspector(isPresented:)`, `.safeAreaInset(.bottom)` for the status bar, and `.searchable(placement: .toolbar)`.
- [x] `SidebarView`: `List(selection: …)` (Optional wrapper around the non-Optional `SidebarFilter`) over Status / Trackers / Folders / Labels sections. Each row is a `Label` + `.badge(count)`. Title-style section headers.
- [x] `TorrentListView`: `Table(selection:)` with narrow column set — Name (StatusDot + truncating text), Size 74pt, Progress 130pt (thin tinted `ProgressView` + %), Down 78pt, ETA 66pt. Numeric columns `.monospacedDigit()`. Context menu: Resume / Pause / Verify / Remove / Remove+data.
- [x] `MainToolbar`: items grouped with `ToolbarSpacer(.fixed)` / `.flexible` separators per LG guidance. Add + Add Magnet · `‖` · Resume + Pause + Remove (destructive role, disabled when no selection) · flexible spacer · Turtle + Inspector toggles. Toolbar buttons are all monochrome — colour stays in the table rows and status bar.
- [x] `StatusBarView`: bottom 28pt strip in `.regularMaterial`, "N torrents · M active" left, ↓/↑ totals + free space + ratio right. No glass — status bar lives in the content layer.
- [x] `InspectorView` placeholder — header (StatusDot + name + meta) and a "tabs land in slice 2" hint; `ContentUnavailableView` when nothing is selected.
- [x] Reusable bits: `StatusDot`, `ProgressBar`, `Formatters.swift` (Int64 bytes/speed, TimeInterval ETA), `DomainDisplay.swift` (status colours + labels for `TorrentStatus` / `TorrentStatusFilter`).
- [x] XCUITest `testMockDataMainWindow` launches with `--mock-data`, asserts the All-Torrents row reads "10", the Downloading row reads "3", and the torrent table renders. 10s timeout — NavigationSplitView + toolbar takes ~3s to materialise its AX tree.

**Validation:** `BuildProject` green · `swift test --package-path Packages/TransmissionCore` 17/17 still pass · `swift format lint --strict` clean · UI test passes.

**Notes:** SwiftUI's toolbar buttons drop their `.accessibilityIdentifier` somewhere between the SwiftUI tree and AppKit's NSToolbar — toolbar items aren't reliably addressable by identifier in XCUITest. Sidebar rows surface theirs as `staticText`s, so we hang the test off those.

### Slice 2 — Inspector tabs ✅

Renders against the current selection (or first torrent if multi-select — header notes "First of N selected").

- [x] `InspectorHeader`: status dot + name (truncating) + subtitle "{size} · {state} · added {relative date}".
- [x] Five tabs — a segmented icon `Picker` (Xcode-inspector idiom) rather than a literal `TabView`, per the "HIG over 1:1 design" direction:
  - **General** — `LabeledContent` KV rows: progress bar + %, "X of Y · A of B pieces" caption, State (tinted capsule badge), Down, Up, Time left, Ratio, Peers; "Details" section: Size, Pieces, Added, Location (mono), Label, Priority, Tracker, Hash (mono, middle-truncated, text-selectable). Error message surfaces as a red label when present.
  - **Files** — `Table` over `torrent.files`: Wanted (checkbox Toggle), Name (`doc` icon + mono), Size, Progress bar+%, Priority (`Picker` High/Normal/Low/Skip — Skip = `wanted: false`). Wired to `store.setFilesWanted` / `store.setFilePriority`.
  - **Peers** — `Table`: Address (country chip + mono IP), Client, Flags (mono), %, Down, Up. `ContentUnavailableView` overlay when no peers.
  - **Trackers** — tier-grouped `GroupBox` cards: state dot, host (mono), status line (red on error), seeds/leechers/downloads (monochrome — colour stays on the state dot).
  - **Options** — `Form(.grouped)` with progressive disclosure (detail rows appear when their toggle is on): honor global limits, down/up limits (TextField+Stepper+"KB/s"), seed-ratio / idle stops, max peers. Edits a local draft, pushes whole `TorrentOptions` through `store.setOptions` on change.
- [x] Selection changes refresh inspector content instantly; tab content is re-keyed by `.id(torrent.id)` so drafts/scroll reset per torrent but survive 1s polling snapshots.
- [x] XCUITest `testInspectorTabs`: selects torrent #5 (Debian), walks all five tabs, asserts key content in each. Segments are addressable as radio buttons (NSSegmentedControl AX).

**Validation:** `swift test --package-path Packages/TransmissionCore` 20/20 · `BuildProject` green · both XCUITests pass · `swift format lint --strict` clean.

### Slice 3 — Add Torrent sheet (S2, ~½ day)

- [ ] `AddTorrentSheet` `.sheet` from main window. Width 560pt.
- [ ] Segmented `Picker`: From file / From magnet.
  - File path: `.fileImporter(allowedContentTypes: [.init(filenameExtension: "torrent")!])`.
  - Magnet: `TextField` validated against `magnet:?xt=urn:btih:` prefix.
- [ ] `LabeledContent` fields: Destination (path + Choose…), Label (Picker), Priority (Picker).
- [ ] Files Table (max 150pt scroll), header "Files · X of Y selected" with Select All / None links.
- [ ] Toggles: "Start when added" (default on), "Verify local data".
- [ ] Footer in `.regularMaterial`: "Total to download · **5.9 GB**" left, Cancel + "Add Torrent" `.glassProminent` right.
- [ ] On submit: `await service.add(...)`; the mock service inserts a new fake torrent + tick progresses it.
- [ ] Drag-drop entry: `.dropDestination(for: URL.self)` on the main window opens the sheet pre-filled.

### Slice 4 — Servers manager + switcher (S3, ~1 day)

- [ ] **Refactor:** `ServerProfileStore` already exists and supports multiple profiles, but `ContentView` only shows the first one. Rework so the store carries an `activeProfileID` and views are scoped to it.
- [ ] **S3b — Toolbar switcher** (replaces principal Menu placeholder from Slice 1): Menu titled "Switch Server" with rows = each profile (status dot + name + live "5 active · ↓ 21.4 MB/s" subtitle) + checkmark on active + "Manage Servers…" footer item.
- [ ] **S3a — Connection manager** as a separate `Window` (registered in `TransmissionSwiftApp.body`) opened from "Manage Servers…". 900×580. `NavigationSplitView` master-detail. List on the left (`server.rack` + name + host:port + status dot, with add/remove footer). Detail = `Form` with Connection / Authentication / Options sections + "Test Connection" inline result.
- [ ] Move the current `AddServerForm.swift` content into this window's detail-edit mode (replace its single-profile use).
- [ ] Switching server tears down + restarts the polling task; meanwhile `ConnectionState = .connecting` (drives Slice 6's skeleton state).

### Slice 5 — Preferences (S4, ~½ day)

- [ ] `Settings { TabView { … } }` scene with four panes: General (`gearshape`), Speed (`tortoise`), Network (`globe`), Remote (`server.rack`).
- [ ] Each pane is a `Form(.grouped)` of `Section`s with the fields listed in the README §S4.
- [ ] `@AppStorage` for app-side prefs (display, badge, show-add-dialog…). Session-side prefs (speed limits, port, encryption, blocklist) get a `SessionSettings` struct backed by mock today, by `session-set` later.
- [ ] Day-of-week toggle row for turtle schedule: `HStack` of 7 `Toggle(isOn:).toggleStyle(.button)` with `.tint(.accentColor)`.

### Slice 6 — Empty / error states (S5, ~½ day)

- [ ] `ConnectionState` already exists in the store from Slice 0. Wire it into `MainWindow` so the *list pane* swaps to a `ContentUnavailableView` when appropriate, while sidebar/toolbar/statusbar stay rendered:
  - **No torrents:** `ContentUnavailableView("No Torrents Yet", systemImage: "arrow.down.circle", description: …)` + primary "Add Torrent…" `.glassProminent` + secondary "Add Magnet Link…".
  - **No search results:** `ContentUnavailableView.search(text: query)` variant + "Clear Search" / "Reset Filters" buttons.
  - **Disconnected:** red `exclamationmark.triangle`, body refs host:port, primary "Reconnect" + "Server Settings…". Toolbar server chip + status bar turn red.
  - **Connecting:** `Table` of 6 placeholder rows with `.redacted(reason: .placeholder)`; status bar reads "Connecting to {name}…".
- [ ] Add a debug menu (only with `--mock-data`) to flip connection state, for screenshot/test purposes.

### Slice 7 — Wire real RPC (the actual backend)

Only once Slices 0–6 land. No UI changes in this slice; only `TransmissionRPC` + `TransmissionCore`.

- [ ] Extend `TransmissionClient` protocol with the methods Slice 0's `TorrentService` needs (torrent-get with explicit field list, torrent-add, torrent-set, torrent-start, torrent-stop, torrent-remove, free-space, session-set, session-get).
- [ ] Add Codable request/response types per method (lots of fields; refer to `reference/rpc-spec-*.md`).
- [ ] `RPCTorrentService` conforms to `TorrentService`, owns adaptive polling (5s when visible, paused when window is in background — `ScenePhase` from the environment passed in).
- [ ] App boot: if `--mock-data` not set → use `RPCTorrentService` with the active profile.
- [ ] Capture fresh fixtures from the live daemon (see `reference/README.md` for the recipe) for every new method.
- [ ] Re-run the XCUITest suite against the real daemon (opt-in via the existing `TEST_RUNNER_TRANSMISSION_E2E=1` flag).

---

## Out of scope

- S1 variants B (bottom drawer) and C (rich rows + floating inspector). Build only if the user asks.
- iPad/iPhone layouts.
- Adaptive polling rate based on whether any torrent is transferring (mentioned in `ARCHITECTURE.md` §5 as future work).
- Offline torrent list cache.
- App icon, About box.

## Open questions

- **Slice 7's RPC fields.** `torrent-get` accepts a field list — we should pick the minimum set the UI uses (≈25 fields) rather than `fields=all`. List those in Slice 0's domain mapping and carry forward.
- **Server switching while polling.** The handoff implies an instant switch; we need to confirm the polling task cancellation is well-behaved (likely a `Task.cancel()` on the previous one + a `.connecting` flash).
- **Per-torrent labels.** Transmission v4 exposes labels via RPC. Older daemons (v3) don't. Decide whether to gate the Labels section in the sidebar / inspector on `session.version >= 4`.

## Result notes

(Fill in as slices complete, matching `first-slice.md`'s pattern.)

### Slice 1 follow-ups (post-merge polish, 2026-06-11)

Landed after the slice was first marked done. All built + UI test passes.

- **Inspector relocated.** `.inspector(isPresented:)` moved from the detail view to the outer `NavigationSplitView` so it sits as a peer pane to the whole split view (not as a child of the detail). Reason: with `.searchable` also on the detail, the search field's toolbar slot was rendering over the inspector area, looking off. New placement also stops the inspector content from creeping behind the toolbar's Liquid Glass.
- **Name column min-width 240pt (`.width(min: 240, ideal: 400)`).** Other columns are fixed at Size 74 / Progress 130 / Down 78 / ETA 66 (total 348). Below ~588pt total, the table now flips into horizontal scroll instead of squeezing the Name to nothing.
- **Sortable columns.** Each `TableColumn` gained a `value:` keypath: `\.name`, `\.size`, `\.progress`, `\.downloadSpeed`, and a fileprivate `\.etaSortKey` (Optional<TimeInterval> isn't directly Comparable through `KeyPathComparator`, so we collapse nil and .infinity to `+∞`). `sortOrder` is `@State` on `TorrentListView`. Persisting "last sort" across launches gets `@AppStorage` later — natural fit when slice 5 (Preferences) lands.
- **Horizontal rubber-band killed.** `.scrollBounceBehavior(.basedOnSize, axes: .horizontal)` on the Table. Important footgun: this modifier's `axes:` parameter defaults to `.vertical`, so the first attempt (`.scrollBounceBehavior(.basedOnSize)` with no axes) silently configured the wrong axis. Vertical bounce is left at default — `axes:` is opt-in per axis.
- **Status bar `+` button removed.** Came from the design mock as a "quick add" but duplicated the toolbar Add — on macOS, the toolbar is the canonical home for that action. Turtle toggle in the status bar still present pending a verdict on whether to keep it (same duplication critique applies).
- **Progress bar animation suppression** (in progress / awaiting user verification):
  - First pass: `.animation(nil, value: value)` on the `ProgressView`. Didn't work — `ProgressView` is `NSProgressIndicator` on macOS and lerps `value` implicitly via something the explicit-value form of `.animation(nil)` didn't cover.
  - Second pass (current): `.transaction { $0.animation = nil }` on the outer `HStack` in `ProgressBar`. Wipes inherited animation context for the whole subtree. Trade-off: natural 1-second progress ticks now snap rather than smoothly fill — fine for a polling app.
  - If the second pass still doesn't kill it, escalation path is dropping NSProgressIndicator entirely and rolling a custom bar from `Capsule()` overlays — `Capsule` frame changes don't animate without an explicit animation context, so it would be guaranteed snappy.
- **Better framing for the filter-change UX.** Instead of suppressing cell-content animation, the *right* mental model is: animate **row inserts/deletes** (which macOS Table already does on its own via NSTableView diffing) and keep cell content snap. Like Mail / Finder. That's why the `.transaction` approach above is the correct one in spirit — the row animation happens naturally underneath; we just need to stop the cell content from fighting it.

### Slice 2 notes (2026-06-11)

- **Service surface grew after all** (the earlier "UI scaffolding only" note was optimistic — the Files/Options tabs are interactive). `TorrentService` gained `setFilesWanted`, `setFilePriority`, `setOptions`; `TorrentStore` mirrors them as actions; `MockTorrentService` mutates + broadcasts. 3 new core tests (20 total).
- **New domain type `TorrentOptions`** on `Torrent.options` — Bool+value pairs (`downloadLimited` + `downloadLimitKBps`, `seedRatioLimited` + `seedRatioLimit`, …). Deliberately collapses Transmission's tri-state seed-limit modes (global/single/unlimited) to the two the UI exposes; slice 7 maps the Bools to `seedRatioMode` 0/1.
- **Tabs are a segmented icon `Picker`, not `TabView`** — matches the Xcode/Finder inspector idiom and avoids TabView's content chrome fighting edge-to-edge `Table`s in Files/Peers.
- **Options tab state flow:** local `@State` draft seeded from `torrent.options` in `init`, whole struct pushed via `onChange`. The `.id(torrent.id)` re-key in `InspectorView` is what resets the draft on selection change — without it `@State` survives and shows the previous torrent's values.
- **New app-target files** (filesystem-synced, no pbxproj edits): `InspectorGeneralTab/FilesTab/PeersTab/TrackersTab/OptionsTab.swift`; `InspectorView.swift` rewritten.
- **XCUITest learning:** SwiftUI's segmented picker segments *are* addressable — they surface as `radioButtons` keyed by each segment's `accessibilityLabel` (set on the `Image` options). Toolbar buttons remain unaddressable per slice 1's note, but the inspector defaults to visible so the test never needs the toolbar toggle.

### Picking up from a new session

- **Slice 3 is up next** — Add Torrent sheet (S2): segmented file/magnet picker, destination/label/priority fields, files table, footer with `.glassProminent` CTA. Needs a new `add(...)` on `TorrentService` + mock insert behaviour, and the `.dropDestination` entry point on the main window.
- **Still awaiting visual verification by Jonas** (carried from slice 1 — agent can't eyeball these):
  - `ProgressBar` `.transaction { $0.animation = nil }` killing the bar lerp on filter switch. Escalation: custom `Capsule()` bar.
  - Inspector placement (no search-field weirdness, no glass-creep) — now more visible with the slice 2 tabs in.
  - Horizontal bounce gone with `axes: .horizontal`.
  - New: the five inspector tabs at the 280–322pt widths — Files/Peers tables may want column tweaks once seen on a real display.
- **Open polish items** that aren't blocking but worth doing soon:
  - Decide on the status-bar turtle button — keep or drop?
  - Decide on persisting sort order across launches (slice 5 / `@AppStorage`).
  - Filter-change row animations: see whether NSTableView's natural insert/delete animation is enough, or whether we want to wrap the filter binding in `withAnimation` for a more pronounced slide.
