import AppKit
import SwiftUI
import TransmissionCore

enum TorrentRowAction {
    case resume
    case pause
    case setPriority(TorrentPriority)
    case verify
    case reannounce
    case remove
    case removeAndDeleteData
    case editLabels
    case setLocation
    case rename
    case sendToShortcut(name: String)
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
    /// Local tag→colour assignments (TagColorStore). External to the torrent
    /// rows, so a change forces a visible-cell refresh rather than riding the
    /// row poll guard.
    var tagColors: [String: TagColor] = [:]
    var onRowAction: ((TorrentRowAction, [Torrent.ID]) -> Void)?
    var onInspectorRequest: (() -> Void)?
    /// Per-server "Open with…" entries (see `OpenMapping`).
    var mappings: [OpenMapping] = []
    var onOpenMapping: ((OpenMapping, [Torrent.ID]) -> Void)?
    /// The name of the Shortcut "Send to Shortcut" runs, from Preferences.
    var shortcutName: String?

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
        // each column's isHidden state under autosaveName. All columns are
        // added up front with their defaults (hidden-by-default ones start
        // hidden per spec). The autosave properties are set *after* the columns
        // exist: AppKit's restore pass runs when the autosave name is set and
        // matches saved state to columns by identifier, so setting it before
        // any columns exist makes the restore a no-op and leaves every column
        // at its default on each launch.
        let coordinator = context.coordinator
        coordinator.tableView = tableView
        for spec in TorrentTableColumns.all {
            let column = coordinator.makeColumn(from: spec)
            column.isHidden = spec.hiddenByDefault
            tableView.addTableColumn(column)
        }
        // Grouped visibility menu: the native AppKit header menu is a flat
        // list, unfindable at 30+ columns, so the header gets a custom menu
        // with one submenu per `TorrentTableColumnGroup`. Toggling flips the
        // real column's isHidden, so autosave persistence keeps working.
        let headerMenu = coordinator.makeHeaderMenu()
        coordinator.headerMenu = headerMenu
        tableView.headerView?.menu = headerMenu
        tableView.autosaveName = "torrentsTableColumns"
        tableView.autosaveTableColumns = true

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
            tagColors: tagColors,
            onSortChange: onSortChange,
            onRowAction: onRowAction,
            onInspectorRequest: onInspectorRequest,
            mappings: mappings,
            shortcutName: shortcutName,
            onOpenMapping: onOpenMapping)
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
            tagColors: tagColors,
            onSortChange: onSortChange,
            onRowAction: onRowAction,
            onInspectorRequest: onInspectorRequest,
            mappings: mappings,
            shortcutName: shortcutName,
            onOpenMapping: onOpenMapping)
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
        var tagColors: [String: TagColor] = [:]
        var onRowAction: ((TorrentRowAction, [Torrent.ID]) -> Void)?
        var onInspectorRequest: (() -> Void)?
        var mappings: [OpenMapping] = []
        var shortcutName: String?
        var onOpenMapping: ((OpenMapping, [Torrent.ID]) -> Void)?
        weak var rowMenu: NSMenu?
        weak var headerMenu: NSMenu?

        private var rowStore = TorrentTableRowStore()
        /// Current projection, owned by `rowStore`; exposed for the
        /// data-source, menu and delegate reads below.
        private var displayedRows: [TorrentRowDisplay] { rowStore.displayedRows }
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
            tagColors: [String: TagColor],
            onSortChange: ((TransmissionCore.TableColumn, Bool) -> Void)?,
            onRowAction: ((TorrentRowAction, [Torrent.ID]) -> Void)?,
            onInspectorRequest: (() -> Void)?,
            mappings: [OpenMapping],
            shortcutName: String?,
            onOpenMapping: ((OpenMapping, [Torrent.ID]) -> Void)?
        ) {
            self.downloadDirectoryBase = downloadDirectoryBase
            self.sortState = sortState
            self.actionsEnabled = actionsEnabled
            self.labelsSupported = labelsSupported
            self.tagColors = tagColors
            self.onSortChange = onSortChange
            self.onRowAction = onRowAction
            self.onInspectorRequest = onInspectorRequest
            self.mappings = mappings
            self.shortcutName = shortcutName
            self.onOpenMapping = onOpenMapping
        }

        /// Single funnel for all row mutations. Selection is a separate concern
        /// restored by `syncSelectionFromBinding` after every update; an
        /// incremental diff can slot in here later without a redesign. The
        /// decision is made by the pure `TorrentTableRowStore`; this only
        /// performs the resulting AppKit side effect.
        func apply(rows newRows: [Torrent]) {
            let update = rowStore.apply(
                rows: newRows,
                downloadDirectoryBase: downloadDirectoryBase,
                tagColors: tagColors)
            guard let tableView else { return }
            switch update {
            case .none: return
            case .reload: tableView.reloadData()
            case .refreshVisible: refreshVisibleCells(in: tableView)
            }
        }

        /// Mirrors external `store.list.selectedTorrentIDs` changes into the table,
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
        /// semantics; blank-area right-click acts on the selection. The rule
        /// lives in `TorrentTableSelection` so it is testable headlessly.
        private func affectedIDs(forRows rows: IndexSet) -> Set<Torrent.ID> {
            TorrentTableSelection.affectedIDs(
                rows: rows,
                displayedRows: displayedRows,
                selection: selectionBinding.wrappedValue)
        }

        @objc func doubleClicked(_ sender: Any?) {
            guard let tableView, tableView.clickedRow >= 0 else { return }
            onInspectorRequest?()
        }

        @objc func contextMenuItemClicked(_ sender: NSMenuItem) {
            if let payload = sender.representedObject as? MenuPayload {
                onRowAction?(payload.action, payload.ids)
            } else if let payload = sender.representedObject as? OpenMappingPayload {
                onOpenMapping?(payload.mapping, payload.ids)
            }
        }

        final class MenuPayload {
            let action: TorrentRowAction
            let ids: [Torrent.ID]

            init(action: TorrentRowAction, ids: [Torrent.ID]) {
                self.action = action
                self.ids = ids
            }
        }

        final class OpenMappingPayload {
            let mapping: OpenMapping
            let ids: [Torrent.ID]

            init(mapping: OpenMapping, ids: [Torrent.ID]) {
                self.mapping = mapping
                self.ids = ids
            }
        }

        private static let destructiveItemTag = 1
        private static let editLabelsItemTag = 2
        private static let openMappingItemTag = 3
        private static let setLocationItemTag = 4
        private static let hideColumnItemTag = 5
        private static let renameItemTag = 6

        /// Title + SF-symbol glyph for a torrent-priority context-menu item.
        /// Mirrors the priority column's glyphs (TorrentPriority.systemImage).
        private static func priorityMenuItemContent(_ priority: TorrentPriority) -> (String, String) {
            (priority.displayLabel, priority.systemImage)
        }

        private func populateRowMenu(_ menu: NSMenu, ids: [Torrent.ID]) {
            menu.removeAllItems()
            let priorities = ids.compactMap { id in
                displayedRows.first { $0.id == id }?.torrent.priority
            }
            let specs = TorrentRowMenu.items(
                ids: ids,
                priorities: priorities,
                actionsEnabled: actionsEnabled,
                labelsSupported: labelsSupported,
                mappings: mappings,
                shortcutName: shortcutName)
            let payload = { action in MenuPayload(action: action, ids: ids) }
            let actionItem = { (title: String, symbol: String, action: TorrentRowAction) in
                let item = NSMenuItem(
                    title: title,
                    action: #selector(TorrentTableRepresentable.Coordinator.contextMenuItemClicked(_:)),
                    keyEquivalent: "")
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
                item.target = self
                item.representedObject = payload(action)
                return item
            }
            let destructiveItem = {
                (title: String, symbol: String, action: TorrentRowAction, enabled: Bool) in
                let item = DestructiveMenuItem(
                    title: title,
                    baseColor: enabled ? .systemRed : .secondaryLabelColor)
                item.action = #selector(TorrentTableRepresentable.Coordinator.contextMenuItemClicked(_:))
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
                item.target = self
                item.representedObject = payload(action)
                item.tag = Self.destructiveItemTag
                item.isEnabled = enabled
                return item
            }
            let openItem = { (mapping: OpenMapping) in
                let title =
                    mapping.action == .finder
                    ? "Reveal in \(mapping.name)" : "Open with \(mapping.name)"
                let symbol: String =
                    mapping.action == .finder ? "folder" : "arrow.up.right.square"
                let item = NSMenuItem(
                    title: title,
                    action: #selector(TorrentTableRepresentable.Coordinator.contextMenuItemClicked(_:)),
                    keyEquivalent: "")
                item.image = NSImage(
                    systemSymbolName: symbol,
                    accessibilityDescription: title)
                item.target = self
                item.representedObject = OpenMappingPayload(mapping: mapping, ids: ids)
                item.tag = Self.openMappingItemTag
                return item
            }

            menu.autoenablesItems = false
            var index = 0
            while index < specs.count {
                let spec = specs[index]
                switch spec.kind {
                case .priority:
                    // A run of consecutive priority entries becomes one submenu.
                    let submenu = NSMenu()
                    while index < specs.count {
                        guard case .priority(let priority) = specs[index].kind else { break }
                        let prioritySpec = specs[index]
                        let (title, symbol) = Self.priorityMenuItemContent(priority)
                        let priorityItem = actionItem(title, symbol, .setPriority(priority))
                        priorityItem.state = prioritySpec.isChecked ? .on : .off
                        priorityItem.isEnabled = prioritySpec.isEnabled
                        submenu.addItem(priorityItem)
                        index += 1
                    }
                    let container = NSMenuItem(title: "Priority", action: nil, keyEquivalent: "")
                    container.image = NSImage(
                        systemSymbolName: "arrow.up.arrow.down",
                        accessibilityDescription: "Priority")
                    container.submenu = submenu
                    // Every priority entry shares one enablement, so the first
                    // is representative of the whole submenu.
                    container.isEnabled = submenu.items.first?.isEnabled ?? false
                    menu.addItem(container)
                    continue
                case .resume:
                    let item = actionItem("Resume", "play.fill", .resume)
                    item.isEnabled = spec.isEnabled
                    menu.addItem(item)
                case .pause:
                    let item = actionItem("Pause", "pause.fill", .pause)
                    item.isEnabled = spec.isEnabled
                    menu.addItem(item)
                case .separator:
                    menu.addItem(.separator())
                case .verify:
                    let item = actionItem("Verify Local Data", "checkmark.shield", .verify)
                    item.isEnabled = spec.isEnabled
                    menu.addItem(item)
                case .reannounce:
                    let item = actionItem("Update Tracker", "megaphone", .reannounce)
                    item.isEnabled = spec.isEnabled
                    menu.addItem(item)
                case .sendToShortcut(let name):
                    let item = actionItem(
                        "Send to “\(name)”", "square.and.arrow.up", .sendToShortcut(name: name))
                    item.isEnabled = spec.isEnabled
                    menu.addItem(item)
                case .mapping(let mapping):
                    let item = openItem(mapping)
                    item.isEnabled = spec.isEnabled
                    menu.addItem(item)
                case .editLabels:
                    let item = actionItem("Edit Labels…", "tag", .editLabels)
                    item.tag = Self.editLabelsItemTag
                    item.isEnabled = spec.isEnabled
                    menu.addItem(item)
                case .setLocation:
                    let item = actionItem("Set Location…", "folder", .setLocation)
                    item.tag = Self.setLocationItemTag
                    item.isEnabled = spec.isEnabled
                    menu.addItem(item)
                case .rename:
                    let item = actionItem("Rename…", "pencil", .rename)
                    item.tag = Self.renameItemTag
                    item.isEnabled = spec.isEnabled
                    menu.addItem(item)
                case .remove:
                    menu.addItem(
                        destructiveItem("Remove\u{2026}", "trash", .remove, spec.isEnabled))
                case .removeAndDeleteData:
                    menu.addItem(
                        destructiveItem(
                            "Remove and Delete Data\u{2026}", "trash.fill", .removeAndDeleteData,
                            spec.isEnabled))
                }
                index += 1
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

        /// Builds the grouped header visibility menu: one submenu per column
        /// group, each item toggling its column's isHidden, plus a trailing
        /// hide/reset section. States refresh in `menuNeedsUpdate` just before
        /// the menu pops.
        func makeHeaderMenu() -> NSMenu {
            let menu = NSMenu()
            menu.delegate = self
            for group in TorrentTableColumnGroup.allCases {
                let submenu = NSMenu()
                for spec in TorrentTableColumns.all where spec.group == group {
                    let item = NSMenuItem(
                        title: spec.title,
                        action: #selector(TorrentTableRepresentable.Coordinator.toggleColumnVisibility(_:)),
                        keyEquivalent: "")
                    item.target = self
                    item.representedObject = spec.column.rawValue
                    submenu.addItem(item)
                }
                let groupItem = NSMenuItem(title: group.rawValue, action: nil, keyEquivalent: "")
                groupItem.submenu = submenu
                menu.addItem(groupItem)
            }
            menu.addItem(.separator())
            let hideItem = NSMenuItem(
                title: "Hide This Column",
                action: #selector(TorrentTableRepresentable.Coordinator.hideClickedColumn(_:)),
                keyEquivalent: "")
            hideItem.target = self
            hideItem.tag = Self.hideColumnItemTag
            menu.addItem(hideItem)
            let resetItem = NSMenuItem(
                title: "Reset Columns",
                action: #selector(TorrentTableRepresentable.Coordinator.resetColumnsToDefaults(_:)),
                keyEquivalent: "")
            resetItem.target = self
            menu.addItem(resetItem)
            return menu
        }

        @objc func toggleColumnVisibility(_ sender: NSMenuItem) {
            guard let tableView,
                let rawValue = sender.representedObject as? String
            else { return }
            let identifier = NSUserInterfaceItemIdentifier(rawValue)
            guard let column = tableView.tableColumns.first(where: { $0.identifier == identifier }) else { return }
            // Never hide the last visible column — an empty table gives no
            // header to right-click back from.
            let visibleCount = tableView.tableColumns.count(where: { !$0.isHidden })
            if !column.isHidden, visibleCount <= 1 { return }
            column.isHidden.toggle()
        }

        /// Hides the header cell the menu was invoked from (`clickedColumn` is
        /// valid in `menuNeedsUpdate`, where the target is captured).
        @objc func hideClickedColumn(_ sender: NSMenuItem) {
            guard let tableView,
                let rawValue = sender.representedObject as? String
            else { return }
            let identifier = NSUserInterfaceItemIdentifier(rawValue)
            guard let column = tableView.tableColumns.first(where: { $0.identifier == identifier }),
                !column.isHidden
            else { return }
            let visibleCount = tableView.tableColumns.count(where: { !$0.isHidden })
            if visibleCount <= 1 { return }
            column.isHidden = true
        }

        /// Restores the spec defaults: visibility, widths, and column order.
        /// Autosave persists the restored state, so it survives relaunches.
        /// Sort order is untouched — that lives in the store, not the table.
        @objc func resetColumnsToDefaults(_ sender: NSMenuItem) {
            guard let tableView else { return }
            for (index, spec) in TorrentTableColumns.all.enumerated() {
                guard
                    let column = tableView.tableColumns.first(where: {
                        $0.identifier == spec.identifier
                    })
                else { continue }
                column.isHidden = spec.hiddenByDefault
                column.width = spec.idealWidth
                let currentIndex = tableView.column(withIdentifier: spec.identifier)
                if currentIndex != -1, currentIndex != index {
                    tableView.moveColumn(currentIndex, toColumn: index)
                }
            }
        }

        /// Refreshes each header-menu item's checkmark from its column's
        /// isHidden, disabling the sole visible column so it can't be hidden.
        /// Also retargets the "Hide …" item at the right-clicked column.
        func refreshHeaderMenu() {
            guard let menu = headerMenu, let tableView else { return }
            let visibleCount = tableView.tableColumns.count(where: { !$0.isHidden })
            for groupItem in menu.items {
                guard let submenu = groupItem.submenu else { continue }
                for item in submenu.items {
                    guard let rawValue = item.representedObject as? String else { continue }
                    let identifier = NSUserInterfaceItemIdentifier(rawValue)
                    guard let column = tableView.tableColumns.first(where: { $0.identifier == identifier })
                    else { continue }
                    item.state = column.isHidden ? .off : .on
                    item.isEnabled = column.isHidden || visibleCount > 1
                }
            }
            guard let hideItem = menu.items.first(where: { $0.tag == Self.hideColumnItemTag }) else { return }
            guard let index = invokedHeaderColumnIndex(in: tableView) else {
                hideItem.title = "Hide This Column"
                hideItem.representedObject = nil
                hideItem.isEnabled = false
                return
            }
            let column = tableView.tableColumns[index]
            let title =
                TorrentTableColumns.all.first(where: { $0.identifier == column.identifier })?.title
                ?? column.identifier.rawValue
            hideItem.title = "Hide “\(title)”"
            hideItem.representedObject = column.identifier.rawValue
            hideItem.isEnabled = !column.isHidden && visibleCount > 1
        }

        /// Index of the header column the visibility menu was invoked from.
        /// Hit-tests the current right-click in the header: `clickedColumn` is
        /// only updated for row clicks, so it stays -1 here and the Hide item
        /// would never arm. Falls back to `clickedColumn` for keyboard-invoked
        /// menus, where there is no mouse event.
        func invokedHeaderColumnIndex(in tableView: NSTableView) -> Int? {
            if let headerView = tableView.headerView, let event = NSApp.currentEvent {
                let point = headerView.convert(event.locationInWindow, from: nil)
                if headerView.bounds.contains(point) {
                    let column = headerView.column(at: point)
                    if column >= 0, tableView.tableColumns.indices.contains(column) {
                        return column
                    }
                }
            }
            let clicked = tableView.clickedColumn
            if clicked >= 0, tableView.tableColumns.indices.contains(clicked) { return clicked }
            return nil
        }

        private func restoreSelection() {
            guard let tableView else { return }
            let selection = selectionBinding.wrappedValue
            let tableSel = TorrentTableSelection.ids(
                at: tableView.selectedRowIndexes, displayedRows: displayedRows)
            guard selection != tableSel else { return }
            let indexes = TorrentTableSelection.rowIndexes(
                for: selection, displayedRows: displayedRows)
            // Guard the echo: selectRowIndexes posts tableViewSelectionDidChange
            // synchronously; without this flag the write-back loop (or a stale
            // table's empty write) could clobber the store's selection.
            isRestoringSelection = true
            tableView.selectRowIndexes(indexes, byExtendingSelection: false)
            isRestoringSelection = false
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
                            downloadDirectoryBase: downloadDirectoryBase,
                            tagColors: tagColors))
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
                downloadDirectoryBase: downloadDirectoryBase,
                tagColors: tagColors))
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView else { return }
        // Ignore changes caused by our own programmatic selection (restore
        // after reload) so the write-back can't clobber the store.
        guard !isRestoringSelection else { return }
        let ids = TorrentTableSelection.ids(
            at: tableView.selectedRowIndexes, displayedRows: displayedRows)
        guard ids != selectionBinding.wrappedValue else { return }
        selectionBinding.wrappedValue = ids
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        // Snapshot replay is read-only: still render the persisted sort
        // indicator, but don't forward a user sort attempt to the store, where
        // it would persist `tablePreferences` to the real UserDefaults.
        guard actionsEnabled, !isNormalizingSortDescriptors else { return }
        // AppKit promotes the clicked column to PRIMARY, keeping older entries
        // as secondaries. This is a single-sort table: collapse to the primary
        // before resolving it (the `.last` of that list was the original bug —
        // it is the oldest secondary).
        if tableView.sortDescriptors.count > 1,
            let primary = tableView.sortDescriptors.first
        {
            isNormalizingSortDescriptors = true
            tableView.sortDescriptors = [primary]
            isNormalizingSortDescriptors = false
        }
        guard let normalized = TorrentTableSort.normalize(tableView.sortDescriptors) else {
            return
        }
        onSortChange?(normalized.column, normalized.ascending)
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
        } else if menu === headerMenu {
            refreshHeaderMenu()
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
