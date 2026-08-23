import AppKit
import SwiftUI
import TransmissionCore

enum TorrentRowAction {
    case resume
    case pause
    case verify
    case remove
    case removeAndDeleteData
    case editLabels
}

struct TorrentTableRepresentable: NSViewRepresentable {
    let rows: [Torrent]
    @Binding var selection: Set<Torrent.ID>
    var downloadDirectoryBase: String?
    var sortColumnID: String?
    var sortAscending: Bool
    var onSortChange: ((TransmissionCore.TableColumn, Bool) -> Void)?
    var actionsEnabled: Bool
    var labelsSupported: Bool = true
    var onRowAction: ((TorrentRowAction, [Torrent.ID]) -> Void)?
    var onInspectorRequest: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.rowHeight = 28
        tableView.usesAutomaticRowHeights = false
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.allowsColumnResizing = true
        tableView.allowsColumnReordering = true
        // Fill the window width: the Name column (first, always visible)
        // absorbs spare horizontal space, so the elastic column is the one you
        // most want to widen. Once columns exceed the clip width, the
        // horizontal scroller takes over.
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        // Inset style + alternating colors: rounded selection highlight and the
        // zebra striping the SwiftUI Table used to provide.
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.gridStyleMask = []
        tableView.floatsGroupRows = false
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.headerView = NSTableHeaderView()
        tableView.setAccessibilityIdentifier("torrents.table")

        // Column layout persistence: NSTableView autosaves order, widths and
        // each column's isHidden state under autosaveName. All 20 columns are
        // added up front (hidden-by-default ones start hidden per spec); on
        // subsequent launches the autosave restores the user's layout over
        // these defaults.
        tableView.autosaveName = "torrentsTableColumns"
        tableView.autosaveTableColumns = true

        let coordinator = context.coordinator
        coordinator.tableView = tableView
        for spec in TorrentTableColumns.all {
            let column = coordinator.makeColumn(from: spec)
            column.isHidden = spec.hiddenByDefault
            tableView.addTableColumn(column)
        }

        // Row context menu: NSTableView has NO menuForRows delegate method. The
        // canonical mechanism is tableView.menu + NSMenuDelegate.menuNeedsUpdate,
        // which rebuilds the menu from tableView.clickedRow before it pops.
        // An empty base menu here would pop as a blank flash — the row items must
        // be populated by the delegate in menuNeedsUpdate.
        let rowMenu = NSMenu()
        rowMenu.delegate = coordinator
        coordinator.rowMenu = rowMenu
        tableView.menu = rowMenu

        coordinator.configure(
            downloadDirectoryBase: downloadDirectoryBase,
            sortState: Coordinator.SortState(columnID: sortColumnID, ascending: sortAscending),
            actionsEnabled: actionsEnabled,
            labelsSupported: labelsSupported,
            onSortChange: onSortChange,
            onRowAction: onRowAction,
            onInspectorRequest: onInspectorRequest)
        tableView.dataSource = coordinator
        tableView.delegate = coordinator
        tableView.target = coordinator
        tableView.doubleAction = #selector(TorrentTableRepresentable.Coordinator.doubleClicked(_:))

        coordinator.syncSortIndicator()

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        let coordinator = context.coordinator
        coordinator.tableView = tableView
        // The coordinator's binding is snapshotted at makeCoordinator; refresh it
        // every update so a re-injected store or re-created representable never
        // drives selection through a stale reference.
        coordinator.updateSelectionBinding($selection)
        coordinator.configure(
            downloadDirectoryBase: downloadDirectoryBase,
            sortState: Coordinator.SortState(columnID: sortColumnID, ascending: sortAscending),
            actionsEnabled: actionsEnabled,
            labelsSupported: labelsSupported,
            onSortChange: onSortChange,
            onRowAction: onRowAction,
            onInspectorRequest: onInspectorRequest)
        // Indicators before rows: the header reacts on the same frame as the
        // click, even if the row reload takes an extra layout pass.
        coordinator.syncSortIndicator()
        coordinator.apply(rows: rows)
        coordinator.syncSelectionFromBinding()
    }

    @MainActor
    final class Coordinator: NSObject {
        struct SortState: Equatable {
            var columnID: String?
            var ascending: Bool
        }

        /// Reassigned on every `updateNSView` so it can never go stale across
        /// representable recreation or store re-injection.
        private(set) var selectionBinding: Binding<Set<Torrent.ID>>
        weak var tableView: NSTableView?
        var downloadDirectoryBase: String?
        var onSortChange: ((TransmissionCore.TableColumn, Bool) -> Void)?
        var sortState: SortState?
        var actionsEnabled = true
        var labelsSupported = true
        var onRowAction: ((TorrentRowAction, [Torrent.ID]) -> Void)?
        var onInspectorRequest: (() -> Void)?
        weak var rowMenu: NSMenu?

        private(set) var displayedRows: [TorrentRowDisplay] = []
        private var lastDownloadDirectoryBase: String?
        private var lastAppliedSortState: SortState?
        private var isNormalizingSortDescriptors = false
        private var isRestoringSelection = false

        init(selection: Binding<Set<Torrent.ID>>) {
            selectionBinding = selection
        }

        func updateSelectionBinding(_ binding: Binding<Set<Torrent.ID>>) {
            selectionBinding = binding
        }

        /// Single funnel for the representable's input props, shared by
        /// `makeNSView` and `updateNSView` so the two call sites can't drift.
        func configure(
            downloadDirectoryBase: String?,
            sortState: SortState?,
            actionsEnabled: Bool,
            labelsSupported: Bool,
            onSortChange: ((TransmissionCore.TableColumn, Bool) -> Void)?,
            onRowAction: ((TorrentRowAction, [Torrent.ID]) -> Void)?,
            onInspectorRequest: (() -> Void)?
        ) {
            self.downloadDirectoryBase = downloadDirectoryBase
            self.sortState = sortState
            self.actionsEnabled = actionsEnabled
            self.labelsSupported = labelsSupported
            self.onSortChange = onSortChange
            self.onRowAction = onRowAction
            self.onInspectorRequest = onInspectorRequest
        }

        /// Single funnel for all row mutations. Selection is a separate concern
        /// restored by `syncSelectionFromBinding` after every update; an
        /// incremental diff can slot in here later without a redesign.
        func apply(rows newRows: [Torrent]) {
            let newDisplays = newRows.map(TorrentRowDisplay.init)
            let change = Self.classifyChange(from: displayedRows, to: newDisplays)
            let baseChanged = downloadDirectoryBase != lastDownloadDirectoryBase
            guard change != .none || baseChanged else { return }
            displayedRows = newDisplays
            lastDownloadDirectoryBase = downloadDirectoryBase
            guard let tableView else { return }
            if change == .structural {
                tableView.reloadData()
            } else {
                refreshVisibleCells(in: tableView)
            }
        }

        /// One pass over both arrays, folding the old "id sequence" and
        /// "field equality" guards into a single comparison so the poll never
        /// pays for two full scans. `.structural` when the row set or id order
        /// changed (reload), `.values` when only cell content changed (refresh
        /// visible cells in place), `.none` when nothing moved.
        static func classifyChange(
            from old: [TorrentRowDisplay], to new: [TorrentRowDisplay]
        ) -> TorrentTableRepresentable.Coordinator.ChangeKind {
            guard old.count == new.count else { return .structural }
            var valuesChanged = false
            for (lhs, rhs) in zip(old, new) {
                if lhs.id != rhs.id { return .structural }
                if lhs != rhs { valuesChanged = true }
            }
            return valuesChanged ? .values : .none
        }

        enum ChangeKind: Equatable {
            case none, values, structural
        }

        /// Mirrors external `store.selectedTorrentIDs` changes into the table,
        /// including after structural reloads. Compares before writing so the
        /// delegate → binding → updateNSView round-trip settles instead of looping.
        func syncSelectionFromBinding() {
            restoreSelection()
        }

        /// Reflects the store's persisted sort into native header indicators.
        /// Setting `tableView.sortDescriptors` also drives indicator rendering;
        /// the resulting delegate callback is absorbed by the store's equality
        /// guard so it cannot loop.
        func syncSortIndicator() {
            guard let tableView else { return }
            guard sortState != lastAppliedSortState else { return }
            lastAppliedSortState = sortState
            if let id = sortState?.columnID,
                let column = TransmissionCore.TableColumn(rawValue: id)
            {
                tableView.sortDescriptors = [
                    NSSortDescriptor(
                        key: column.rawValue,
                        ascending: sortState?.ascending ?? true)
                ]
            } else {
                tableView.sortDescriptors = []
            }
        }

        // MARK: - Row context menu & interaction

        /// Clicked rows ∪ selection, matching the old SwiftUI context-menu
        /// semantics; blank-area right-click acts on the selection.
        private func affectedIDs(forRows rows: IndexSet) -> Set<Torrent.ID> {
            let selection = selectionBinding.wrappedValue
            let rowIDs = Set(
                rows.compactMap { row in
                    displayedRows.indices.contains(row) ? displayedRows[row].id : nil
                })
            if rows.isEmpty { return selection }
            let clickInsideSelection = rows.allSatisfy { row in
                displayedRows.indices.contains(row) && selection.contains(displayedRows[row].id)
            }
            return clickInsideSelection ? selection : rowIDs
        }

        @objc func doubleClicked(_ sender: Any?) {
            guard let tableView, tableView.clickedRow >= 0 else { return }
            onInspectorRequest?()
        }

        @objc func contextMenuItemClicked(_ sender: NSMenuItem) {
            guard let payload = sender.representedObject as? MenuPayload else { return }
            onRowAction?(payload.action, payload.ids)
        }

        final class MenuPayload {
            let action: TorrentRowAction
            let ids: [Torrent.ID]

            init(action: TorrentRowAction, ids: [Torrent.ID]) {
                self.action = action
                self.ids = ids
            }
        }

        private static let destructiveItemTag = 1
        private static let editLabelsItemTag = 2

        private func populateRowMenu(_ menu: NSMenu, ids: [Torrent.ID]) {
            menu.removeAllItems()
            let canAct = actionsEnabled && !ids.isEmpty
            let payload = { action in MenuPayload(action: action, ids: ids) }
            let item = { (title: String, symbol: String, action: TorrentRowAction) in
                let item = NSMenuItem(
                    title: title,
                    action: #selector(TorrentTableRepresentable.Coordinator.contextMenuItemClicked(_:)),
                    keyEquivalent: "")
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
                item.target = self
                item.representedObject = payload(action)
                return item
            }
            let destructiveItem = { (title: String, symbol: String, action: TorrentRowAction) in
                let item = DestructiveMenuItem(
                    title: title,
                    baseColor: canAct ? .systemRed : .secondaryLabelColor)
                item.action = #selector(TorrentTableRepresentable.Coordinator.contextMenuItemClicked(_:))
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
                item.target = self
                item.representedObject = payload(action)
                item.tag = Self.destructiveItemTag
                return item
            }

            menu.autoenablesItems = false
            menu.addItem(item("Resume", "play.fill", .resume))
            menu.addItem(item("Pause", "pause.fill", .pause))
            menu.addItem(.separator())
            menu.addItem(item("Verify Local Data", "checkmark.shield", .verify))
            menu.addItem(.separator())
            let editLabelsItem = item("Edit Labels…", "tag", .editLabels)
            editLabelsItem.tag = Self.editLabelsItemTag
            menu.addItem(editLabelsItem)
            menu.addItem(.separator())
            menu.addItem(destructiveItem("Remove\u{2026}", "trash", .remove))
            menu.addItem(
                destructiveItem("Remove and Delete Data\u{2026}", "trash.fill", .removeAndDeleteData))
            for menuItem in menu.items where menuItem.action != nil {
                menuItem.isEnabled =
                    menuItem.tag == Self.editLabelsItemTag ? canAct && labelsSupported : canAct
            }
        }

        /// Row context menu rebuild. Called by `menuNeedsUpdate` just before the
        /// menu pops; `clickedRow` is valid here. Replaces the old (nonexistent)
        /// `menuForRows` delegate method — NSTableView has no such hook.
        private func rebuildRowMenu() {
            guard let menu = rowMenu, let tableView else { return }
            // Raw NSTableView does not select on right-click; SwiftUI Table did.
            // Restore that: clicking outside the selection moves the selection to
            // the clicked row first (inside the selection keeps multi-select).
            // Unlike `restoreSelection`, this select is NOT wrapped in
            // `isRestoringSelection` — the selection change here is a real user
            // action and must propagate back through the binding to the store.
            let clickedRow = tableView.clickedRow
            if clickedRow >= 0 {
                let selection = selectionBinding.wrappedValue
                let clickInsideSelection =
                    displayedRows.indices.contains(clickedRow)
                    && selection.contains(displayedRows[clickedRow].id)
                if !clickInsideSelection {
                    tableView.selectRowIndexes(
                        IndexSet(integer: clickedRow), byExtendingSelection: false)
                }
            }
            let rows = clickedRow >= 0 ? IndexSet(integer: clickedRow) : IndexSet()
            populateRowMenu(menu, ids: Array(affectedIDs(forRows: rows)))
        }

        // MARK: - Column construction

        func makeColumn(from spec: TorrentTableColumnSpec) -> NSTableColumn {
            let column = NSTableColumn(identifier: spec.identifier)
            column.headerCell = PaddedTableHeaderCell(textCell: spec.title)
            column.minWidth = spec.minWidth
            column.maxWidth = spec.maxWidth
            column.width = spec.idealWidth
            column.resizingMask = [.userResizingMask, .autoresizingMask]
            column.sortDescriptorPrototype = NSSortDescriptor(
                key: spec.column.rawValue, ascending: true)
            return column
        }

        private func restoreSelection() {
            guard let tableView else { return }
            let selection = selectionBinding.wrappedValue
            let tableSel = selectedRowIDs(in: tableView)
            guard selection != tableSel else { return }
            let indexes = IndexSet(
                displayedRows.enumerated().compactMap { row, torrent in
                    selection.contains(torrent.id) ? row : nil
                })
            // Guard the echo: selectRowIndexes posts tableViewSelectionDidChange
            // synchronously; without this flag the write-back loop (or a stale
            // table's empty write) could clobber the store's selection.
            isRestoringSelection = true
            tableView.selectRowIndexes(indexes, byExtendingSelection: false)
            isRestoringSelection = false
        }

        private func selectedRowIDs(in tableView: NSTableView) -> Set<Torrent.ID> {
            Set(
                tableView.selectedRowIndexes.compactMap { row in
                    displayedRows.indices.contains(row) ? displayedRows[row].id : nil
                })
        }

        private func refreshVisibleCells(in tableView: NSTableView) {
            let visible = tableView.rows(in: tableView.visibleRect)
            for row in visible.location..<visible.upperBound
            where displayedRows.indices.contains(row) {
                for column in tableView.tableColumns where !column.isHidden {
                    let columnIndex = tableView.column(withIdentifier: column.identifier)
                    guard columnIndex != -1,
                        let tableColumn = TransmissionCore.TableColumn(
                            rawValue: column.identifier.rawValue),
                        let cell = tableView.view(
                            atColumn: columnIndex, row: row, makeIfNecessary: false
                        ) as? TorrentTableCellView
                    else { continue }
                    cell.configure(
                        content: TorrentCellContent.make(
                            for: tableColumn,
                            row: displayedRows[row],
                            downloadDirectoryBase: downloadDirectoryBase))
                }
            }
        }
    }
}

extension TorrentTableRepresentable.Coordinator: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        displayedRows.count
    }

    func tableView(
        _ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int
    ) -> Any? {
        nil
    }
}

extension TorrentTableRepresentable.Coordinator: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard displayedRows.indices.contains(row), let tableColumn,
            let column = TransmissionCore.TableColumn(rawValue: tableColumn.identifier.rawValue)
        else { return nil }
        let reuseID = NSUserInterfaceItemIdentifier(
            TorrentTableColumns.cellReuseIdentifierPrefix + column.rawValue)
        let cell =
            tableView.makeView(withIdentifier: reuseID, owner: self) as? TorrentTableCellView
            ?? TorrentTableCellView()
        cell.identifier = reuseID
        cell.configure(
            content: TorrentCellContent.make(
                for: column,
                row: displayedRows[row],
                downloadDirectoryBase: downloadDirectoryBase))
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView else { return }
        // Ignore changes caused by our own programmatic selection (restore
        // after reload) so the write-back can't clobber the store.
        guard !isRestoringSelection else { return }
        let ids = Set(
            tableView.selectedRowIndexes.compactMap { row in
                displayedRows.indices.contains(row) ? displayedRows[row].id : nil
            })
        guard ids != selectionBinding.wrappedValue else { return }
        selectionBinding.wrappedValue = ids
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        // Snapshot replay is read-only: still render the persisted sort
        // indicator, but don't forward a user sort attempt to the store, where
        // it would persist `tablePreferences` to the real UserDefaults.
        guard actionsEnabled else { return }
        // AppKit promotes the clicked column to PRIMARY of its descriptor list,
        // keeping older entries as secondaries. We are a single-sort table:
        // take the primary, collapse the list to just it, and forward it.
        // (.last here was the original bug — it is the oldest secondary.)
        guard !isNormalizingSortDescriptors else { return }
        guard let descriptor = tableView.sortDescriptors.first else { return }
        if tableView.sortDescriptors.count > 1 {
            isNormalizingSortDescriptors = true
            tableView.sortDescriptors = [descriptor]
            isNormalizingSortDescriptors = false
        }
        guard let key = descriptor.key,
            let column = TransmissionCore.TableColumn(rawValue: key)
        else { return }
        onSortChange?(column, descriptor.ascending)
    }

    func tableView(_ tableView: NSTableView, userCanChangeVisibilityOf column: NSTableColumn) -> Bool {
        // Enables the native header checkmark menu for hide/show. Autosave
        // persists each column's isHidden state under `autosaveName`.
        true
    }
}

extension TorrentTableRepresentable.Coordinator: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === rowMenu {
            rebuildRowMenu()
        }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        // Attributed titles bypass NSMenu's automatic hover styling (white text
        // on the highlight), so the destructive red would otherwise stay red
        // against the blue highlight. `isHighlighted` KVO never fires — AppKit
        // writes that property's backing ivar directly — so this callback is
        // the reliable highlight signal: AppKit sends it before each highlight
        // change, and once more with nil when the menu closes.
        guard menu === rowMenu else { return }
        for menuItem in menu.items {
            if let destructive = menuItem as? DestructiveMenuItem {
                destructive.applyHighlight(highlighted: menuItem === item)
            }
        }
    }
}

/// Header cell with the same leading inset the body cells use, so column titles
/// don't sit flush against the divider. `NSTableHeaderCell` draws the title and
/// sort indicator itself in `drawInterior` — it does NOT route text placement
/// through `titleRect(forBounds:)` — so that's the hook to inset.
private final class PaddedTableHeaderCell: NSTableHeaderCell {
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        var inset = cellFrame
        inset.origin.x += TorrentTableCellView.cellInset
        inset.size.width -= TorrentTableCellView.cellInset
        super.drawInterior(withFrame: inset, in: controlView)
    }
}

/// Destructive context-menu item. Attributed titles bypass NSMenu's automatic
/// hover styling (white text on the highlight), so the destructive red would
/// otherwise stay red against the blue highlight. Recoloring is driven by the
/// menu delegate's `willHighlight` callback (`NSMenuItem.isHighlighted` KVO
/// never fires: AppKit writes its backing ivar directly).
private final class DestructiveMenuItem: NSMenuItem {
    private let baseColor: NSColor

    init(title: String, baseColor: NSColor) {
        self.baseColor = baseColor
        super.init(title: title, action: nil, keyEquivalent: "")
        applyHighlight(highlighted: false)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyHighlight(highlighted: Bool) {
        let color: NSColor = highlighted ? .white : baseColor
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [.foregroundColor: color])
    }
}
