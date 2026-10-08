import AppKit
import SwiftUI
import Testing
import TransmissionCore

@testable import TransmissionSwift

/// The AppKit adapter around the pure table logic: the grouped column-visibility
/// header menu. These need an `NSTableView`, so they are integration-flavoured
/// rather than pure units.
@Suite("TorrentTableRepresentable.Coordinator")
@MainActor
struct TorrentTableCoordinatorTests {
    private func makeHeaderTable() -> (
        NSTableView, TorrentTableRepresentable.Coordinator, NSMenu
    ) {
        let coordinator = TorrentTableRepresentable.Coordinator(
            selection: .constant(Set<Torrent.ID>()))
        let tableView = NSTableView()
        coordinator.tableView = tableView
        for spec in TorrentTableColumns.all {
            let column = coordinator.makeColumn(from: spec)
            column.isHidden = spec.hiddenByDefault
            tableView.addTableColumn(column)
        }
        // The coordinator holds the table and menu weakly (the scroll view
        // and header own them in production); the test keeps both alive.
        let menu = coordinator.makeHeaderMenu()
        coordinator.headerMenu = menu
        return (tableView, coordinator, menu)
    }

    private func actionItem(rawValue: String) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.representedObject = rawValue
        return item
    }

    private func column(_ tableView: NSTableView, _ id: String) -> NSTableColumn {
        tableView.tableColumns.first(where: { $0.identifier.rawValue == id })!
    }

    @Test func headerToggle_hidesAndShowsColumn() {
        let (tableView, coordinator, _) = makeHeaderTable()
        coordinator.toggleColumnVisibility(actionItem(rawValue: "name"))
        #expect(column(tableView, "name").isHidden)
        coordinator.toggleColumnVisibility(actionItem(rawValue: "name"))
        #expect(!column(tableView, "name").isHidden)
    }

    @Test func headerHide_hidesByIdentifier() {
        let (tableView, coordinator, _) = makeHeaderTable()
        coordinator.hideClickedColumn(actionItem(rawValue: "size"))
        #expect(column(tableView, "size").isHidden)
    }

    @Test func headerHide_refusesLastVisibleColumn() {
        let (tableView, coordinator, _) = makeHeaderTable()
        for col in tableView.tableColumns where col.identifier.rawValue != "name" {
            col.isHidden = true
        }
        coordinator.hideClickedColumn(actionItem(rawValue: "name"))
        #expect(!column(tableView, "name").isHidden)
    }

    @Test func headerReset_restoresVisibilityWidthAndOrder() {
        let (tableView, coordinator, _) = makeHeaderTable()
        column(tableView, "name").isHidden = true
        column(tableView, "size").width = 54
        tableView.moveColumn(0, toColumn: 5)
        #expect(tableView.tableColumns.first?.identifier.rawValue != "name")

        coordinator.resetColumnsToDefaults(NSMenuItem())

        #expect(!column(tableView, "name").isHidden)
        #expect(column(tableView, "size").width == 74)
        #expect(
            tableView.tableColumns.map(\.identifier)
                == TorrentTableColumns.all.map(\.identifier))
    }

    @Test func headerHide_withoutClickStaysDisabled() {
        // Headless: no mouse event and clickedColumn == -1, so the Hide item
        // must fall back to disabled instead of arming at a stale column.
        // (Keep `tableView` alive: the coordinator holds it weakly.)
        let (tableView, coordinator, menu) = makeHeaderTable()
        #expect(coordinator.invokedHeaderColumnIndex(in: tableView) == nil)
        coordinator.refreshHeaderMenu()
        let hideItem = menu.items.first(where: {
            $0.action == #selector(TorrentTableRepresentable.Coordinator.hideClickedColumn(_:))
        })!
        #expect(hideItem.title == "Hide This Column")
        #expect(!hideItem.isEnabled)
    }
}
