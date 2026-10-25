# AppKit table and editor layout

The AppKit code is split so its non-UI logic runs headless in
`TransmissionSwiftTests`.

| File | Owns |
|---|---|
| `TorrentRowDisplay` | the `Equatable` projection the table diffs on |
| `TorrentCellContent` | the cell's display value and `make(for:)` builder |
| `TorrentTableCellView` | the `NSTableCellView` renderer |
| `TagPillView`, `TorrentProgressBarView` | the cell's tag chip and progress bar |
| `TorrentTableRowStore` | `apply(rows:...) -> Update` (`.none` / `.refreshVisible` / `.reloadAll`) and `classifyChange` |
| `TorrentTableSelection` | row ⇄ torrent-id mapping for clicks and selection restore |
| `TorrentTableSort` | AppKit sort descriptors → one column and direction |
| `TorrentRowMenu` | the context-menu enablement matrix as a pure spec |
| `TorrentTableRepresentable` | the representable and a thin `Coordinator` adapter |
| `MappingEditorModel`, `MappingEditorSheet`, `OpenMappingPlaceholders`, `MappingsPrefsPane` | the mapping editor's state, sheet, catalog and pane |

Rules that keep it from rotting:

- Pure logic takes values and returns decisions; it must not import `AppKit`.
  `NSSortDescriptor` is Foundation and the one allowed AppKit-adjacent input.
- The `Coordinator` performs the side effects (`reloadData`,
  `refreshVisibleCells`, menu construction) and nothing else.
- Behaviour here gets a direct test, not only a preview:
  `TorrentTableRowStoreTests`, `TorrentTableSelectionTests`,
  `TorrentTableSortTests`, `TorrentRowMenuTests`, `TorrentCellContentTests`,
  `TorrentRowDisplayTests`.
