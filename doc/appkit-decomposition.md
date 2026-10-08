# Decomposing the large AppKit / editor files

Status: **complete.** All slices (A, B1–B4, C) have landed. This is item 1 of
the senior review's maintainability leftovers (see the session that produced
`doc/torrentstore-split.md`).

## Progress

| Slice | State |
|---|---|
| A — split `TorrentTableCellView.swift` into five files | done |
| B1 — `TorrentTableRowStore` (updateNSView diff/apply decision) | done |
| B2 — `TorrentTableSelection` (index ⇄ ID mapping) | done |
| B3 — `TorrentTableSort` (primary-descriptor normalisation) | done |
| B4 — `TorrentRowMenu` spec (context-menu enablement model) | done |
| C — `OpenMappingEditor.swift` split | done |

Slice A added direct `TorrentCellContent.make` coverage (name/progress/label/
priority/queuePosition/errorMessage/downloadFolder). Slice B moved `classifyChange`
into `TorrentTableRowStore` and pinned its `Update` outcomes plus the selection
and sort rules in `TorrentTableLogicTests`. B4 moved the row context-menu
enablement matrix into a pure `TorrentRowMenu` spec; the `Coordinator` now maps
that spec to `NSMenuItem`s. `TorrentTableRepresentable.swift`'s `Coordinator` is
a thin AppKit adapter over the four pure types. Slice C split `OpenMappingEditor`
into the list view, `MappingEditorModel`, `MappingEditorSheet` and an
`OpenMappingPlaceholders` catalog.

## Why

Three app-target files carry most of the remaining "one file owns too much"
risk. Unlike the `TorrentStore` split (which was Core-only, pure Swift), these
are AppKit views, so the goal is not to shrink line count alone but to pull the
**non-UI logic out where it can be tested without a window**.

| File | Lines | What it holds |
|---|---:|---|
| `TransmissionSwift/TorrentList/TorrentTableCellView.swift` | 1086 | pure row projection, pure cell-content value + builder, the `NSTableCellView`, two helper views |
| `TransmissionSwift/TorrentList/TorrentTableRepresentable.swift` | 824 | the `NSViewRepresentable`, its delegate/data-source `Coordinator`, two AppKit helper classes |
| `TransmissionSwift/Preferences/OpenMappingEditor.swift` | 777 | editor list view, field-state model, a large sheet, placeholder catalog |

`TorrentTableLogicTests.swift` already tests the pure pieces that leaked out
(`TorrentRowDisplay` equality, `classifyChange`, header-menu logic, formatters).
This plan grows that suite as it creates more such seams.

## Constraints

- **No behaviour change.** Moves are moves; any semantic change is called out in
  the commit body.
- App target uses filesystem-synchronized groups: new files under
  `TransmissionSwift/` are picked up from disk, no pbxproj edits.
- Keep AppKit types in the app target; keep extracted logic free of
  `NSTableView`/`NSMenu` so it runs headless in the unit test target.
- Swift 6 mode, `swift-format`, Swift Testing, no force-unwraps, no new deps.
- One focused commit per slice. Verify each with `just test-packages-strict`,
  `just build`, app unit tests, `just test-snapshot`.

## Slice A — split `TorrentTableCellView.swift` (mechanical, low risk)

Pure file moves; the code is already written against the `TorrentCellContent`
seam. Target files (all in `TransmissionSwift/TorrentList/`):

| New file | Contents | Current lines |
|---|---|---|
| `TorrentRowDisplay.swift` | the `Equatable` poll-guard projection | 8–55 |
| `TorrentCellContent.swift` | the `Equatable` display value + `make(for:…)` builder extension | 60–576 |
| `TorrentTableCellView.swift` | the `NSTableCellView` renderer only | 578–881 |
| `TagPillView.swift` | the capsule tag chip | 883–1018 |
| `TorrentProgressBarView.swift` | the layer-drawn progress bar | 1020–1086 |

`TagPillView` / `TorrentProgressBarView` are referenced only from the cell view,
so they stay `internal` in their own files.

Test work while moving: `TorrentCellContent.make` has no direct coverage today.
Add a handful of assertions to `TorrentTableLogicTests` (shape/alignment/colour
for `name`, `progress`, `label`/`pills`, `priority`, `queuePosition`, and the
empty/dash cases) so the seam the reviewer named is pinned.

Risk: none material. If the move-only diff is large, it is still mechanical.

## Slice B — extract the table's non-UI logic (the real win)

`TorrentTableRepresentable.swift` is 824 lines mostly because the `Coordinator`
mixes four concerns. Each becomes a pure type in the app target, with the
`Coordinator` reduced to an AppKit adapter.

### B1. Row-update decision (`updateNSView` diff/apply)

Today the gating lives across `apply(rows:)` + `classifyChange` + the
`lastTagColors` / `lastDownloadDirectoryBase` bookkeeping. Extract into a pure
value type:

```swift
struct TorrentTableRowStore {
    private(set) var displayedRows: [TorrentRowDisplay]
    enum Update { case none, refreshVisible, reloadAll }
    mutating func apply(
        rows: [Torrent],
        downloadDirectoryBase: String?,
        tagColors: [String: TagColor]) -> Update
}
```

`Coordinator.apply` keeps the `tableView.reloadData()` / `refreshVisibleCells`
side effect and does nothing else. `classifyChange` moves in (existing tests
repoint). Tests: `.none` on identical, `.refreshVisible` on content-only change,
`.reloadAll` on id/count/order change, `.refreshVisible` when only `tagColors`
changed, and the base-directory path.

### B2. Selection mapping

`affectedIDs(forRows:)` and the two `selectedRowIDs` / restore-index helpers are
pure functions of `displayedRows` + `selection` + an `IndexSet`. Extract:

```swift
enum TorrentTableSelection {
    static func affectedIDs(rows: IndexSet, displayedRows: [TorrentRowDisplay], selection: Set<Torrent.ID>) -> Set<Torrent.ID>
    static func rowIndexes(ids: Set<Torrent.ID>, displayedRows: [TorrentRowDisplay]) -> IndexSet
    static func ids(at rows: IndexSet, displayedRows: [TorrentRowDisplay]) -> Set<Torrent.ID>
}
```

Tests: right-click inside/outside a multi-selection, blank-area fallback,
unknown-index safety.

### B3. Sort normalisation

`sortDescriptorsDidChange` collapses AppKit's promoted-primary list to a single
descriptor. Extract the decision:

```swift
enum TorrentTableSort {
    static func normalize(_ descriptors: [NSSortDescriptor])
        -> (descriptors: [NSSortDescriptor], column: TableColumn, ascending: Bool)?
}
```

Tests: primary wins over secondaries, already-single list, non-table key, empty.

### B4. Row context-menu model (largest sub-step, optional)

`populateRowMenu` (~110 lines) encodes the enablement rules inline. Extract a
pure menu model and let the `Coordinator` map it to `NSMenuItem`s:

```swift
struct TorrentRowMenuSpec {
    enum Item { case resume, pause, priority(TorrentPriority), verify, reannounce,
                mapping(OpenMapping), editLabels, setLocation, rename,
                remove, removeAndDeleteData }
    let item: Item
    let isEnabled: Bool
    let isChecked: Bool  // priorities only
}
enum TorrentRowMenu {
    static func specs(ids: [Torrent.ID], priorities: [Torrent.ID: TorrentPriority],
                      actionsEnabled: Bool, labelsSupported: Bool,
                      mappings: [OpenMapping]) -> [TorrentRowMenuSpec]
}
```

Tests (headless, the point of the exercise): every capability gate
(`labelsSupported` off, multi-select disabling rename/mapping, `actionsEnabled`
off, uniform vs mixed priority checks, mapping items only with a single id).
The `NSMenu` construction and the `DestructiveMenuItem` highlight handling stay
in the Coordinator. Propose doing B1–B3 first and deciding on B4 after, because
B4 carries the most behavioural risk for the least structural gain.

After B, `TorrentTableRepresentable.swift` should be roughly: the representable
(unchanged) + a much thinner delegate adapter + the two private AppKit helpers.

## Slice C — `OpenMappingEditor.swift` (defer)

The seams already exist inside the file (`MappingEditorModel`, the sheet, the
placeholder catalog). Mechanical split:

- `MappingEditorModel.swift` — the field-state model (already non-View)
- `MappingEditorSheet.swift` — the sheet
- `OpenMappingPlaceholders.swift` — the placeholder groups + presets (the file
  comment already calls this a single source of truth, so keep them together)
- `OpenMappingEditor.swift` — the list view + `Placeholder*` support types

Lower priority than A/B: the file is a single feature with a clear entry point,
and the review only lists it as "also large".

## Ordering & scope options

- **A + B, defer C (recommended):** the two AppKit files the review flags as
  highest risk get both the mechanical split and the testable-logic extraction;
  the editor split waits until there's a reason.
- **A only:** mechanical file splits, no new logic seams. Smallest diff.
- **B only:** skip the cosmetic split, go straight for the testable extraction.
- **A + B + C:** everything in this plan, across sessions.

## Risks

| Risk | Mitigation |
|---|---|
| B4 changes menu behaviour | Do B1–B3 first; keep B4 behind a clear before/after test of the enablement matrix |
| Diff/apply extraction regresses the per-second poll (over-reload) | Existing `classifyChange` tests + new `Update` tests pin `.none` for unchanged rows; snapshot UI test exercises repaint |
| Pure `NSSortDescriptor` helper leaks AppKit into "pure" code | `NSSortDescriptor` is Foundation; acceptable, and the project already tests header-menu logic against `NSTableView` in the app unit target |
| Large move-only commit is hard to review | Keep Slice A one commit of pure moves (reviewable with `--color-moved`), Slice B separately |
