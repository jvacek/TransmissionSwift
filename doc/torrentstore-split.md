# Splitting `TorrentStore`

Status: in progress. Phase 1 (TorrentListModel) landed. Target: reduce the
817-line `TorrentStore` (`Packages/TransmissionCore/Sources/TransmissionCore/TorrentStore.swift`)
into a coordinator plus focused `@Observable` collaborators, without a flag-day
rewrite and without changing behaviour.

## Progress

| Phase | State |
|---|---|
| 1 — `TorrentListModel` | done |
| 2 — `SessionModel` | done |
| 3 — `InspectorModel` | not started |
| 4 — `TorrentActionModel` | not started |
| 5 — `TorrentSheetState` | not started |
| 6 — docs / sweep | not started |

Phase 1 moved the torrent list, its derivation (facets, visible rows), selection,
search, filters, sort, `downloadDirectory` and the sort preference onto
`TorrentListModel`; `TorrentStore` now exposes it as `store.list`. Views read
`store.list.<member>` (the one binding, `searchQuery`, uses
`@Bindable var list = store.list`). New direct suite:
`TorrentListModelTests.swift`.

Phase 2 moved the session-level daemon state (settings, turtle speed, free
space, version, stats, port, label support) and its reads/writes onto
`SessionModel` as `store.session`. The SwiftUI `binding(keyPath:)` /
`effectiveSessionSettings` helpers moved to a `SessionModel` extension
(`PrefsShared.swift`). The poll loop drives it via `session.load(from:)` /
`session.poll(from:)` with the captured service; user actions use the bound
service. New direct suite: `SessionModelTests.swift`.

## Why

`TorrentStore` currently owns, all at once:

- Polling lifecycle and the connection state machine.
- The torrent list plus its derivation (facets, visible rows, selection pruning).
- Search, sidebar filter, sort state and their persistence.
- Inspector detail and inspector presentation.
- Session-level daemon state (speed limits, stats, version, free space, port).
- Every torrent mutation and the app-wide action-error channel.
- Presentation state for five sheets.

Every view reads the whole object from the environment, so every view is
coupled to everything. Tests have to build the whole store to exercise any one
concern. It is the single biggest maintainability liability in the app (see the
review in the session that produced this doc).

## Goals / non-goals

Goals:

- Shrink the coordinator to wiring, the poll loop, and cross-cutting concerns.
- Give each concern one owning type with a clear, testable API.
- Keep the app compiling and its tests green after every slice (no flag day).
- Keep the single-environment-object convenience (previews stay one line).

Non-goals:

- Splitting into separate environment objects. That is an optional later phase
  (see Phase 7); it multiplies the preview/test boilerplate for a coupling win
  we can mostly get by convention here.
- Changing the `TorrentService` protocol (that is a separate finding, tracked
  in the review, not here).
- Moving `TransmissionRPC` types.
- Any behaviour change. If a slice changes behaviour, it is a bug in the slice.

## Constraints that shape the design

These are the SwiftUI / Observation rules the split must respect. Verified
against the current usage in the app target.

1. **Nested `@Observable` observation works.** A view that reads
   `store.list.visibleTorrents` in its body registers a dependency on
   `list.visibleTorrents`; mutating it invalidates the view. SwiftUI's
   observation tracking records every `@Observable` access during body
   evaluation, regardless of which object owns it. So a coordinator can hold
   sub-models and views can read through it.
2. **`@Bindable` binds a sub-model directly.** `@Bindable` produces bindings
   from a value, not from "the environment object". In `body`:
   ```swift
   @Environment(TorrentStore.self) private var store
   var body: some View {
       @Bindable var list = store.list      // local, one per body
       @Bindable var ui = store.ui
       // $list.searchQuery, $ui.showAddTorrent, ...
   }
   ```
   This is the migration target for `$store.searchQuery`,
   `$store.showAddTorrent`, `$store.inspectorTab`, etc. Multiple `@Bindable`
   locals in one body are fine.
3. **One environment object.** `.environment(store)` stays as-is in
   `TransmissionSwiftApp` and every `#Preview`. Sub-models are reached via
   `store.<slice>`, so no preview or test signature churns just from the split.
4. **Sub-models are `@MainActor final class` + `@Observable`.** Same isolation
   as today; the coordinator mutates them from its `@MainActor` poll task.
5. **No child→parent strong references.** Sub-models that need to raise the
   shared error channel take it as a sink (closure or weak protocol), not a
   back-reference to the coordinator. Keeps ownership acyclic.

## Target architecture

One injected coordinator, five collaborators.

```
TorrentStore  (coordinator, @Observable, in the environment)
├── owns service, streamTask, freeSpaceTask
├── owns connection state, isConnected, actionsEnabled
├── runs the poll loop; distributes snapshots + session info to collaborators
├── owns lastActionError (the single alert channel)
├── owns torrentForOpening(...), captureSnapshot(...)
├── owns the open* sheet entry points (calls U + capability checks)
│
├── list:    TorrentListModel    (torrents, derived rows, selection, search,
│                                 filters, sort, downloadDirectory, seeding)
├── session: SessionModel        (sessionSettings, alt-speed, free space,
│                                 version, stats, port, supportsLabels,
│                                 session reads/writes)
├── actions: TorrentActionModel  (all torrent mutations, pendingRemoval)
├── inspector: InspectorModel    (inspectorDetail, visible, tab, fetch)
└── ui:      TorrentSheetState   (sheet presentation booleans/targets)
```

Data flow:

- Poll loop (coordinator) yields a torrent snapshot → `list.setTorrents(...)`
  which runs the prune/facet/visible cascade; yields session info →
  `session.apply(sessionInfo)`.
- User actions → `actions.*` / `session.*` → service → service's
  `refreshAfterMutation` re-yields to the stream → back through the poll loop.
  (This is already how it works; the split does not change it.)
- `lastActionError` is the one mutable channel back into the coordinator.

Naming: keep the class named `TorrentStore` (least churn; it still is the
store of stores). Sub-model file names are their type names.

## Member mapping

Destination key: **C** coordinator, **L** list, **S** session, **A** actions,
**I** inspector, **U** sheet state.

### State

| Member | To | Note |
|---|---|---|
| `torrents` | L | `didSet` cascade becomes `setTorrents(_:)` |
| `connection` | C | drives window states |
| `isConnected` | C | computed off `connection` |
| `actionsEnabled` | C | capability from `service.supportsActions` |
| `lastActionError` | C | shared alert channel |
| `selectedSidebarFilters` | L | |
| `filterSelection` | L | |
| `selectedTorrentIDs` | L | |
| `selectedTorrents` | L | computed |
| `searchQuery` | L | `didSet` → rebuild |
| `facets` | L | derived |
| `visibleTorrents` | L | derived |
| `tablePreferences` | L | sort persistence |
| `downloadDirectory` | L | list-domain; set by C from session |
| `sessionSettings` | S | |
| `isAlternativeSpeedEnabled` | S | |
| `freeSpace` | S | |
| `daemonVersion` | S | |
| `sessionStats` | S | |
| `portIsOpen` | S | |
| `supportsLabels` | S | refreshed with session poll |
| `inspectorDetail` | I | |
| `inspectorVisible` | I | persisted UI pref, but inspector-scoped |
| `inspectorTab` | I | |
| `showAddTorrent`, `addTorrentStartInMagnetMode`, `addTorrentPrefilledURL` | U | |
| `showEditLabels`, `editLabelsTargetIDs` | U | |
| `showSetLocation`, `setLocationTargetIDs` | U | |
| `showRenameTorrent`, `renameTorrentTargetID` | U | |
| `pendingRemoval` | A | owned by the remove flow |
| `service`, `streamTask`, `freeSpaceTask` | C | private |
| `sortColumn`, `sortAscending`, `facetSignature` | L | private |

### Methods

| Member | To | Note |
|---|---|---|
| `init(service:)` | C | constructs collaborators |
| `reconnect`, `pausePolling`, `resumePolling`, `connect(service:)` | C | |
| `setConnectionFailed`, `beginKeychainWait`, `simulateConnection` | C | |
| `setStatusFilter`, `toggle{Tracker,Folder,Label}Filter`, `resetFilters`, `setSidebarFilter(s)`, `toggleSidebarFilter`, `setSortOrder` | L | |
| `seedTorrents`, `seedDownloadDirectory` | L | preview/test helpers |
| `start`, `stop`, `remove`, `verify`, `reannounce` | A | |
| `requestRemove`, `confirmPendingRemoval`, `cancelPendingRemoval` | A | |
| `setFilesWanted`, `setFilePriority`, `setPriority`, `setOptions` | A | |
| `setLabels`, `setLocation`, `renameTorrent`, `add` | A | |
| `toggleAlternativeSpeed`, `updateSessionSettings`, `testPort` | S | |
| `refreshFreeSpace`, `refreshSessionStats` | S | |
| `fetchInspectorDetail` | I | |
| `openAddSheet`, `openEditLabels`, `openSetLocation`, `openRenameTorrent`, `addFromExternalURL` | C | set U fields, after capability checks |
| `torrentForOpening` | C | needs service |
| `captureSnapshot` | C | or a `SnapshotCaptureService` (defer) |
| `recordError` | shared | free `ActionError.from(_:)`, used by A and S |

Note on `recordError`: today only action methods and `testPort` call it, and
`MappingOpener` writes `lastActionError` directly. Keep `lastActionError` on C;
give A and S a sink. `MappingOpener` becomes `store.lastActionError = …` still.

## Cross-cutting concerns

- **Poll loop distribution.** `startStream`/`startFreeSpacePoll` stay on C.
  They call `list.setTorrents(snapshot)`, `session.apply(...)`,
  `list.setDownloadDirectory(...)`. Nothing else touches `service`'s stream.
- **Selection pruning on remove.** `remove` moves to A. It already calls
  `selectedTorrentIDs.subtract(ids)`; becomes
  `list.selectedTorrentIDs.subtract(ids)`. A holds a reference to L (C wires
  it at construction).
- **Inspector refresh after mutation.** `setFilesWanted`/`setFilePriority`/
  `renameTorrent` call `refreshInspectorIfCurrent`. A holds a reference to I
  and calls `inspector.refreshIfShowing(id)`.
- **`downloadDirectory` for filtering.** L owns it; C pushes it from session on
  each poll. `filtered(by:relativeTo:)` already takes it as a parameter.
- **Capability guards** (`actionsEnabled`, `supportsLabels`) stay read at the
  call sites; C's `open*` methods read `actionsEnabled` (C) and
  `session.supportsLabels` (S).
- **SwiftUI `binding(keyPath:)`** extension (app target `PrefsShared.swift`)
  moves to extend `SessionModel`, reads `session.sessionSettings`, calls
  `session.updateSessionSettings`.

## Migration strategy

Compiler-driven, one collaborator per PR. The mechanic for each slice:

1. Add the new collaborator type with the members moved over.
2. Remove those members from `TorrentStore`.
3. Fix every compile error by rewriting `store.<member>` →
   `store.<slice>.<member>` (and `$store.x` → `$list.x` where a binding).
   The compiler enumerates every call site; nothing is missed silently.
4. Split the corresponding tests into the collaborator's own test suite.
5. Verify, merge.

This avoids a temporary facade of 50 passthroughs and avoids a flag day: the
tree compiles and the tests pass at the end of each slice.

Order is by cohesion and dependency, least entangled first:

### Phase 1 — `TorrentListModel` (largest, most self-contained)

Files: new `Packages/TransmissionCore/Sources/TransmissionCore/TorrentListModel.swift`;
edit `TorrentStore.swift`. Move the `torrents` cascade, facets, visible rows,
selection, search, filters, sort, `downloadDirectory`, seeding.
Views touched (rename only): `SidebarView`, `TorrentListView`,
`TorrentTableRepresentable`, `MainToolbar` (selection), `MainWindow`
(`searchQuery` binding, empty-state predicates), `StatusBarView`.
Tests: split list/facet/filter/sort cases out of `TorrentStoreTests.swift` into
`TorrentListModelTests.swift`.
Verify: `just test-core`, `just build`, `just test-snapshot`.

### Phase 2 — `SessionModel`

Files: new `SessionModel.swift`; edit `TorrentStore.swift`; move the
`binding(keyPath:)` extension into a `SessionModel` extension in `PrefsShared.swift`.
Move session state + `toggleAlternativeSpeed`/`updateSessionSettings`/`testPort`/
`refresh*`. The poll loop's session assignments become `session.apply(...)`.
Views: `SpeedPrefsPane`, `NetworkPrefsPane`, `TransfersPrefsPane`,
`ServerStatsPopoverView`, `StatusBarView` (free space/version), `DeveloperPrefsPane`.
Tests: `SessionSettingsTests` gains a `SessionModel` suite; `effectiveSessionSettings`
and binding behaviour get their first direct tests.
Verify: `just test-core`, `just build`.

### Phase 3 — `InspectorModel`

Files: new `InspectorModel.swift`; move `inspectorDetail`, `inspectorVisible`,
`inspectorTab`, `fetchInspectorDetail`, and a new `refreshIfShowing(id)`.
Views: `InspectorView`, all `Inspector*Tab`, `MainWindow` (toggle + width),
`MainToolbar`, `ServersPrefsPane` (uses `inspectorDetail ?? torrents.first`).
Tests: add `InspectorModelTests` around the fetch/refresh-on-mutation path.
Verify: `just test-core`, `just build`.

### Phase 4 — `TorrentActionModel`

Files: new `TorrentActionModel.swift`; new `ActionError.swift` (move `ActionError`
+ add `ActionError.from(_:)`); move all torrent mutations, `pendingRemoval`,
`requestRemove`/`confirm`/`cancel`. Wire A → L (selection prune) and A → I
(inspector refresh). C keeps `lastActionError` and hands A a sink.
Views: `MainToolbar` (start/stop/remove/set-location), `TorrentTableRepresentable`
(context-menu actions), `MappingOpener` (`lastActionError` unchanged),
`EditLabelsSheet`/`SetLocationSheet`/`RenameTorrentSheet` (call `add`/mutations).
Tests: `TorrentStoreTests` mutation cases move to `TorrentActionModelTests`,
with a fake service to assert error surfacing.
Verify: `just test-core`, `just build`, `just test-app`.

### Phase 5 — `TorrentSheetState` + coordinator cleanup

Files: new `TorrentSheetState.swift`; move the sheet booleans/targets; keep the
`open*` entry points and `addFromExternalURL` on C (they check capabilities and
set U). Remove now-dead `TorrentStore` members.
Views: `MainWindow` (sheet bindings become `$ui.*`).
Verify: `just test-core`, `just build`, `just test-app`.

### Phase 6 — Docs + dead-path sweep

- Update `ARCHITECTURE.md` (module-layout section) and `doc/ui-buildout.md`
  ("Output" / pick-up notes) to describe the coordinator + collaborators.
- Delete the temporary test helpers that built a whole `TorrentStore` where a
  single collaborator now suffices (`PreviewStores.swift` shrinks).
- Confirm no `store.<member>` references remain that should have moved
  (`grep -rn 'store\.' TransmissionSwift`).

### Phase 7 (optional) — promote collaborators to environment objects

If true view-level decoupling is wanted later: inject `TorrentListModel`,
`SessionModel`, `InspectorModel` separately and have views request only their
slice. This is mechanical once Phase 1–5 land, and is the only step that
changes preview/test injection. Defer until there is a concrete reason.

## Testing strategy

- Each collaborator gets its own suite. `TorrentListModel` is pure and can be
  tested with arrays only (no service). `SessionModel`/`TorrentActionModel` use
  a fake `TorrentService` to assert request/response and error surfacing.
- Keep the existing end-to-end behaviour tests where they exercise real flows
  (snapshot replay, UI tests).
- Move (do not duplicate) cases out of the 842-line `TorrentStoreTests.swift`;
  it should end up as a small coordinator/wiring suite.
- Pin the invariants that currently live in `didSet` side effects with explicit
  tests before moving them: selection pruning on removal, selection preserved
  on empty snapshot, facet recompute gating, sidebar filter pruning.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Nested `@Observable` doesn't invalidate a view that reads `store.list.x` | Prototype in Phase 1 on one screen (`SidebarView`); it is the smallest observable surface. Fall back to injecting the sub-model directly for that view only if it fails. |
| `@Bindable` on a nested sub-model misbehaves | Bind the sub-model itself (`@Bindable var list = store.list`), never `$store.list.x`. Prototype in Phase 1 (`searchQuery` in `MainWindow`). |
| `didSet` semantics lost when `torrents` moves | Convert `didSet` to an explicit `setTorrents(_:)`; keep the empty-transition guard and cover it with a test. |
| Error channel becomes a cycle | Sink closure capturing C weakly, or a tiny `ActionErrorSink` protocol C conforms to; assert no retain cycle by deinit test. |
| A phase stalls mid-migration and blocks others | Each phase is independently green and mergeable; ordering means a stalled phase never leaves a half-moved collaborator used by a later one. |
| Preview/test churn | One injected object is preserved, so previews only change the member path, not the injection. |

## Open decisions

- Name: keep `TorrentStore`, or rename to `TorrentCoordinator` at the end. Keep
  is lower churn; rename is clearer. Decide before Phase 1.
- Whether `captureSnapshot` gets its own `SnapshotCaptureService` or stays on C.
  Lazy: leave on C, revisit if it grows.
- Whether `downloadDirectory` lives on L (proposed) or S with L reading it at
  rebuild time. Proposed L keeps the list rebuild self-contained.
