// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

//
//  TransmissionSwiftUITests.swift
//  TransmissionSwiftUITests
//
//  Created by Jonas Vacek on 10/06/2026.
//

import AppKit
import XCTest

final class TransmissionSwiftUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Golden path: add a server profile, test the connection, see the
    /// daemon's version. Needs a live daemon, so it is opt-in:
    ///
    ///     TEST_RUNNER_TRANSMISSION_E2E=1 xcodebuild test ...
    ///
    /// with `transmission-daemon` running on localhost:9091, auth dev/devpass.
    @MainActor
    func testAddServerAndTestConnection() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["TRANSMISSION_E2E"] == "1",
            "Set TEST_RUNNER_TRANSMISSION_E2E=1 and run a local transmission-daemon to enable")

        let app = XCUIApplication()
        app.launchArguments = ["--ephemeral-profiles"]
        app.launch()

        // Host defaults to localhost and port to 9091; only credentials needed.
        let username = app.textFields["addServer.username"]
        XCTAssertTrue(username.waitForExistence(timeout: 5))
        username.click()
        username.typeText("dev")

        let password = app.secureTextFields["addServer.password"]
        password.click()
        password.typeText("devpass")

        app.buttons["addServer.save"].click()

        let testButton = app.buttons["server.testConnection"]
        XCTAssertTrue(testButton.waitForExistence(timeout: 5))
        testButton.click()

        // SwiftUI surfaces the Label's text as the element's value, not its label.
        let connected = app.staticTexts.matching(
            NSPredicate(
                format: "label BEGINSWITH %@ OR value BEGINSWITH %@",
                "Connected to Transmission", "Connected to Transmission")
        ).firstMatch
        XCTAssertTrue(connected.waitForExistence(timeout: 10), "Expected the daemon version to render")
    }

    /// Golden path: the torrents table (raw NSTableView since the
    /// nstableview-migration) renders rows. Boots the app on a committed
    /// snapshot fixture (mirrors `MockFixtures`, the design-handoff sample set)
    /// so the test runs anywhere — CI included — with no daemon and no
    /// dependence on the developer's ~/Downloads.
    ///
    /// The app-under-test passes the repo path straight to `--snapshot`: when
    /// built for UI testing, Xcode injects
    /// `com.apple.security.temporary-exception.files.absolute-path.read-only = [/]`
    /// into the app's entitlements, so the sandbox does not block reading the
    /// fixture from the checkout. (Manual `--snapshot` launches still need
    /// ~/Downloads — see AGENTS.md.)
    @MainActor
    func testSnapshotMainWindow() throws {
        guard let fixture = fixtureURL() else {
            throw XCTSkip("Missing committed snapshot fixture")
        }

        let app = snapshotApp(fixture)

        let table = app.tables["torrents.table"]
        XCTAssertTrue(
            table.waitForExistence(timeout: 15),
            "Expected the torrents table to appear in the main window")
        XCTAssertTrue(
            table.cells.firstMatch.waitForExistence(timeout: 10),
            "Expected snapshot data to populate at least one table row")

        // Replay takes its server name from the file's `source.serverName`, so
        // test fixtures show a friendly title instead of "Snapshot — <file>".
        XCTAssertTrue(
            app.windows.matching(NSPredicate(format: "title == %@", "My remote server"))
                .firstMatch.waitForExistence(timeout: 10),
            "Expected the snapshot's server name in the window title")

        // The fixture's first torrent must have decoded through the wire mapping.
        let firstRow = table.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Ubuntu 24.04.2 Desktop")
        ).firstMatch
        XCTAssertTrue(
            firstRow.waitForExistence(timeout: 5),
            "Expected a known fixture torrent name to render")
    }

    /// Daemon-free coverage for the Torrent menu: menu presence, selection
    /// driving enablement (the part that proves `Commands` observe the store),
    /// and the ⌘⇧C copy shortcut. Snapshot replay is read-only, so every
    /// mutation must stay disabled and Copy is the one action that works.
    @MainActor
    func testSnapshotTorrentMenuAndCopyShortcut() throws {
        guard let fixture = fixtureURL() else {
            throw XCTSkip("Missing committed snapshot fixture")
        }

        let pasteboard = NSPasteboard.general
        // Text only: saved NSPasteboardItems stay bound to the pasteboard and
        // can't be written back after clearContents.
        let savedText = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let savedText { pasteboard.setString(savedText, forType: .string) }
        }

        let app = snapshotApp(fixture)

        let table = app.tables["torrents.table"]
        XCTAssertTrue(table.waitForExistence(timeout: 15))
        let cell = table.cells.firstMatch
        XCTAssertTrue(
            cell.waitForExistence(timeout: 10),
            "Expected snapshot data to populate at least one table row")

        let menuBar = app.menuBars.firstMatch
        let torrentMenu = menuBar.menuBarItems["Torrent"]
        XCTAssertTrue(torrentMenu.waitForExistence(timeout: 5), "Expected a Torrent menu")

        // Read-only replay: mutating commands are present but disabled.
        torrentMenu.click()
        let resume = app.menuItems["Resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 3))
        XCTAssertFalse(resume.isEnabled)
        XCTAssertFalse(app.menuItems["Start or Stop All"].isEnabled)
        // SwiftUI does not propagate `.disabled` to a command submenu's parent
        // item, so assert the actions themselves rather than "Priority".
        XCTAssertTrue(app.menuItems["Priority"].waitForExistence(timeout: 3))
        app.menuItems["Priority"].click()
        for name in ["High", "Normal", "Low"] {
            let item = app.menuItems[name]
            XCTAssertTrue(item.waitForExistence(timeout: 3), "Expected the \(name) priority item")
            XCTAssertFalse(item.isEnabled)
        }
        app.typeKey(.escape, modifierFlags: [])
        torrentMenu.click()
        XCTAssertTrue(app.menuItems["Edit Labels…"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.menuItems["Set Location…"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.menuItems["Rename…"].waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])

        // No selection: Copy Magnet Link is off as well.
        let editMenu = menuBar.menuBarItems["Edit"]
        editMenu.click()
        let copyMagnet = app.menuItems["Copy Magnet Link"]
        XCTAssertTrue(copyMagnet.waitForExistence(timeout: 3))
        XCTAssertFalse(copyMagnet.isEnabled)
        app.typeKey(.escape, modifierFlags: [])

        // Selecting a row flips it on, proving the commands track the selection.
        cell.click()
        editMenu.click()
        XCTAssertTrue(copyMagnet.waitForExistence(timeout: 3))
        XCTAssertTrue(waitUntil { copyMagnet.isEnabled })
        app.typeKey(.escape, modifierFlags: [])

        // Mutations stay disabled even with a selection: replay is read-only.
        torrentMenu.click()
        XCTAssertTrue(waitUntil { !app.menuItems["Resume"].isEnabled })
        app.typeKey(.escape, modifierFlags: [])

        // The key equivalent itself, not just the menu item.
        pasteboard.clearContents()
        app.typeKey("c", modifierFlags: [.command, .shift])
        XCTAssertTrue(
            waitUntil { pasteboard.string(forType: .string)?.hasPrefix("magnet:?xt=urn:btih:") == true },
            "Expected ⌘⇧C to copy a magnet link")

        let link = pasteboard.string(forType: .string) ?? ""
        XCTAssertTrue(link.contains("&dn="), "Magnet link is missing the display name: \(link)")
        XCTAssertTrue(link.contains("&tr="), "Magnet link is missing a tracker: \(link)")
        XCTAssertFalse(link.contains("\n"), "One selected row must copy exactly one link")
    }

    /// Daemon-free coverage for list-level commands: ⌘C copies the selected
    /// torrent name through the table's responder-chain copy:, ⌘F focuses the
    /// search field, and ⌘I / ⌃⌘S toggle the inspector and sidebar.
    @MainActor
    func testSnapshotCopyAndViewCommands() throws {
        guard let fixture = fixtureURL() else {
            throw XCTSkip("Missing committed snapshot fixture")
        }

        let pasteboard = NSPasteboard.general
        // Text only: saved NSPasteboardItems stay bound to the pasteboard and
        // can't be written back after clearContents.
        let savedText = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let savedText { pasteboard.setString(savedText, forType: .string) }
        }

        let app = snapshotApp(fixture)

        let table = app.tables["torrents.table"]
        XCTAssertTrue(table.waitForExistence(timeout: 15))
        let ubuntu = table.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Ubuntu 24.04.2 Desktop")
        ).firstMatch
        XCTAssertTrue(ubuntu.waitForExistence(timeout: 10))
        ubuntu.click()

        // Copy is enabled by the table and delivers the torrent name.
        let editMenu = app.menuBars.firstMatch.menuBarItems["Edit"]
        editMenu.click()
        let copy = app.menuItems["Copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 3))
        XCTAssertTrue(waitUntil { copy.isEnabled }, "Expected Copy to enable with a row selected")
        app.typeKey(.escape, modifierFlags: [])

        pasteboard.clearContents()
        app.typeKey("c", modifierFlags: .command)
        XCTAssertTrue(waitUntil { pasteboard.string(forType: .string) != nil })
        XCTAssertEqual(pasteboard.string(forType: .string), "Ubuntu 24.04.2 Desktop (amd64).iso")

        // ⌘F lands in the search field.
        app.typeKey("f", modifierFlags: .command)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        app.typeText("ubuntu")
        XCTAssertTrue(
            waitUntil { (search.value as? String) == "ubuntu" },
            "Expected ⌘F to focus the search field")
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(waitUntil { (search.value as? String ?? "").isEmpty })

        // The View menu exposes both toggles.
        app.menuBars.firstMatch.menuBarItems["View"].click()
        XCTAssertTrue(app.menuItems["Enter Full Screen"].waitForExistence(timeout: 3))
        let inspectorItem =
            app.menuItems["Show Inspector"].exists
            ? app.menuItems["Show Inspector"] : app.menuItems["Hide Inspector"]
        XCTAssertTrue(inspectorItem.exists, "Expected a Show/Hide Inspector item")
        let sidebarItem =
            app.menuItems["Show Sidebar"].exists
            ? app.menuItems["Show Sidebar"] : app.menuItems["Hide Sidebar"]
        XCTAssertTrue(sidebarItem.exists, "Expected a Show/Hide Sidebar item")
        app.typeKey(.escape, modifierFlags: [])

        // Read the state from the toggle's label: the tab picker sits in the
        // toolbar and appears a moment after the pane does.
        let toggle = app.buttons["toolbar.inspector"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        func inspectorVisible() -> Bool { toggle.label == "Hide Inspector" }
        let inspectorWasVisible = inspectorVisible()
        // The app owns this preference. If an assertion aborts the test, put
        // the pane back through the same shortcut instead of leaving the
        // developer's app toggled.
        defer {
            if inspectorVisible() != inspectorWasVisible {
                app.typeKey("i", modifierFlags: .command)
            }
        }
        app.typeKey("i", modifierFlags: .command)
        XCTAssertTrue(waitUntil { inspectorVisible() != inspectorWasVisible })
        app.typeKey("i", modifierFlags: .command)
        XCTAssertTrue(waitUntil { inspectorVisible() == inspectorWasVisible })

        let sidebar = app.descendants(matching: .any)
            .matching(identifier: "sidebar.status.all").firstMatch
        let sidebarWasVisible = sidebar.exists
        defer {
            if sidebar.exists != sidebarWasVisible {
                app.typeKey("s", modifierFlags: [.command, .control])
            }
        }
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(waitUntil { sidebar.exists != sidebarWasVisible })
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(waitUntil { sidebar.exists == sidebarWasVisible })
    }

    /// Type-select is an AppKit delegate path: clicking a row then typing a
    /// prefix must move the selection. The unit test covers the delegate return
    /// value; this proves NSTableView actually consults it.
    @MainActor
    func testSnapshotTypeSelectJumpsToTorrent() throws {
        guard let fixture = fixtureURL() else {
            throw XCTSkip("Missing committed snapshot fixture")
        }

        let app = snapshotApp(fixture)
        let table = app.tables["torrents.table"]
        XCTAssertTrue(table.waitForExistence(timeout: 15))
        XCTAssertTrue(table.cells.firstMatch.waitForExistence(timeout: 10))

        // Select a row first: the inspector shows its tab picker only when a
        // torrent is selected.
        table.cells.firstMatch.click()
        let tabs = app.descendants(matching: .any)
            .matching(identifier: "inspector.tabs").firstMatch
        if !tabs.waitForExistence(timeout: 2) {
            app.typeKey("i", modifierFlags: .command)
        }
        XCTAssertTrue(tabs.waitForExistence(timeout: 5), "Expected the inspector")

        // Focus the table again, then type a prefix of a torrent that is not first.
        table.cells.firstMatch.click()
        app.typeText("debian")

        let selected = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Debian 12.6")
        ).firstMatch
        XCTAssertTrue(
            selected.waitForExistence(timeout: 5),
            "Expected type-select to move the selection to Debian 12.6")
    }

    /// The Files tab uses a real Table. The fixture's Debian torrent has
    /// seven files, so this proves the inspector detail fetch and the new list
    /// both render every row.
    @MainActor
    func testSnapshotFilesTabListsEveryFile() throws {
        guard let fixture = fixtureURL() else {
            throw XCTSkip("Missing committed snapshot fixture")
        }

        let app = snapshotApp(fixture)
        let table = app.tables["torrents.table"]
        XCTAssertTrue(table.waitForExistence(timeout: 15))

        let debian = table.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Debian 12.6")
        ).firstMatch
        XCTAssertTrue(debian.waitForExistence(timeout: 10))
        debian.click()

        let tabs = app.descendants(matching: .any)
            .matching(identifier: "inspector.tabs").firstMatch
        if !tabs.waitForExistence(timeout: 2) {
            app.typeKey("i", modifierFlags: .command)
        }
        XCTAssertTrue(tabs.waitForExistence(timeout: 5), "Expected the inspector")

        let filesTab = tabs.buttons["Files"]
        XCTAssertTrue(filesTab.waitForExistence(timeout: 3), "Expected the Files tab")
        filesTab.click()

        let list = app.descendants(matching: .any)
            .matching(identifier: "inspector.files.list").firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5), "Expected the files list")

        let firstFile = list.staticTexts["debian-12.6.0-amd64-netinst.iso"]
        XCTAssertTrue(
            firstFile.waitForExistence(timeout: 15),
            "Expected the Debian torrent's file rows")
        XCTAssertEqual(list.checkBoxes.count, 7)
    }

    /// Clicking a file row must hand keyboard focus to the files list. SwiftUI
    /// keeps the torrent table as the window's key view otherwise, so arrows
    /// moved the torrent selection while the files list drew a grey highlight.
    @MainActor
    func testSnapshotFilesTabTakesKeyboardFocus() throws {
        guard let fixture = fixtureURL() else {
            throw XCTSkip("Missing committed snapshot fixture")
        }

        let app = snapshotApp(fixture)
        let table = app.tables["torrents.table"]
        XCTAssertTrue(table.waitForExistence(timeout: 15))
        let debian = table.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Debian 12.6")
        ).firstMatch
        XCTAssertTrue(debian.waitForExistence(timeout: 10))
        debian.click()

        let tabs = app.descendants(matching: .any)
            .matching(identifier: "inspector.tabs").firstMatch
        if !tabs.waitForExistence(timeout: 2) {
            app.typeKey("i", modifierFlags: .command)
        }
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        tabs.buttons["Files"].click()

        let list = app.descendants(matching: .any)
            .matching(identifier: "inspector.files.list").firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let firstFile = list.cells.element(boundBy: 0)
        XCTAssertTrue(firstFile.waitForExistence(timeout: 15))
        firstFile.click()

        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(
            waitUntil { list.cells.element(boundBy: 1).isSelected },
            "Expected Down to move the file selection, not the torrent selection")
    }

    /// The table runs under the toolbar (so its header blends in) but must
    /// still inset its rows below it, and it must stop above the status bar.
    @MainActor
    func testSnapshotTableClearsToolbarAndStatusBar() throws {
        guard let fixture = fixtureURL() else {
            throw XCTSkip("Missing committed snapshot fixture")
        }

        let app = snapshotApp(fixture)
        let table = app.tables["torrents.table"]
        let firstRow = table.cells.firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 15))
        let statusBar = app.staticTexts["statusBar.count"]
        XCTAssertTrue(statusBar.waitForExistence(timeout: 5))
        let toolbar = app.toolbars.firstMatch
        XCTAssertTrue(toolbar.waitForExistence(timeout: 5))

        XCTAssertGreaterThanOrEqual(
            firstRow.frame.minY, toolbar.frame.maxY,
            "Expected the first row to start below the toolbar, not under it")
        // The table's own frame, not the last row: the fixture is too short
        // for rows to reach the bottom, but the table fills its clip view.
        XCTAssertLessThanOrEqual(
            table.frame.maxY, statusBar.frame.minY + 1,
            "Expected the table to stop above the status bar, not run under it")
    }

    /// Toolbar buttons speak like the View menu ("Show/Hide Inspector"), and
    /// the icon-only server switcher reads as the server's name.
    @MainActor
    func testSnapshotToolbarLabels() throws {
        guard let fixture = fixtureURL() else {
            throw XCTSkip("Missing committed snapshot fixture")
        }

        let app = snapshotApp(fixture)
        let inspectorButton = app.buttons["toolbar.inspector"]
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 15))
        let before = inspectorButton.label
        XCTAssertTrue(["Show Inspector", "Hide Inspector"].contains(before), "Got \(before)")
        let expected = before == "Show Inspector" ? "Hide Inspector" : "Show Inspector"

        // Toggling persists, so flip it back either way.
        inspectorButton.click()
        defer { inspectorButton.click() }
        XCTAssertTrue(
            waitUntil { inspectorButton.label == expected },
            "Expected the inspector button's label to follow the inspector")

        let switcher = app.descendants(matching: .any)
            .matching(identifier: "toolbar.serverSwitcher").firstMatch
        XCTAssertTrue(switcher.waitForExistence(timeout: 5))
        // The same `.accessibilityLabel` lands in different attributes: macOS 26
        // maps it to AXDescription (XCUITest's label) and leaves the symbol's
        // name in the title; macOS 27 maps it to AXTitle and leaves the label
        // empty. Assert the accessible name, whichever slot holds it.
        let accessibleName = switcher.label.isEmpty ? switcher.title : switcher.label
        XCTAssertEqual(
            accessibleName, "My remote server",
            "Expected the server switcher to read as the server name, not the symbol; "
                + "got label '\(switcher.label)', title '\(switcher.title)'")
    }

    /// Every Peers column fits the inspector's default width, so speeds never
    /// sit off to the right behind a horizontal scroll.
    @MainActor
    func testSnapshotPeersTableFitsInspector() throws {
        guard let fixture = fixtureURL() else {
            throw XCTSkip("Missing committed snapshot fixture")
        }

        let app = snapshotApp(fixture)
        let table = app.tables["torrents.table"]
        XCTAssertTrue(table.waitForExistence(timeout: 15))
        let ubuntu = table.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Ubuntu 24.04.2")
        ).firstMatch
        XCTAssertTrue(ubuntu.waitForExistence(timeout: 10))
        ubuntu.click()

        let tabs = app.descendants(matching: .any)
            .matching(identifier: "inspector.tabs").firstMatch
        if !tabs.waitForExistence(timeout: 2) {
            app.typeKey("i", modifierFlags: .command)
        }
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        tabs.buttons["Peers"].click()

        // SwiftUI exposes the Table as an outline.
        let peers = app.outlines["inspector.peers.table"]
        let firstRow = peers.outlineRows.firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        let lastCell = firstRow.cells.element(boundBy: firstRow.cells.count - 1)
        XCTAssertLessThanOrEqual(
            lastCell.frame.maxX, peers.frame.maxX + 1,
            "Expected the last Peers column to fit inside the inspector")
    }

    /// The Files tab sorts from a Finder-style "Sort By" menu. Picking a key
    /// resorts the rows and starts at that key's natural direction (most
    /// complete first for Progress).
    @MainActor
    func testSnapshotFilesTabSortMenu() throws {
        guard let fixture = fixtureURL() else {
            throw XCTSkip("Missing committed snapshot fixture")
        }

        let app = snapshotApp(fixture)
        let table = app.tables["torrents.table"]
        XCTAssertTrue(table.waitForExistence(timeout: 15))
        let debian = table.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Debian 12.6")
        ).firstMatch
        XCTAssertTrue(debian.waitForExistence(timeout: 10))
        debian.click()

        let tabs = app.descendants(matching: .any)
            .matching(identifier: "inspector.tabs").firstMatch
        if !tabs.waitForExistence(timeout: 2) {
            app.typeKey("i", modifierFlags: .command)
        }
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        tabs.buttons["Files"].click()

        let list = app.descendants(matching: .any)
            .matching(identifier: "inspector.files.list").firstMatch
        let firstRow = list.cells.element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 15))
        // Name order puts the 4% DVD image first.
        XCTAssertTrue(firstRow.staticTexts["4%"].exists)

        let sort = app.descendants(matching: .any)
            .matching(identifier: "inspector.files.sort").firstMatch
        XCTAssertTrue(sort.waitForExistence(timeout: 5))
        sort.click()
        app.menuItems["Progress"].click()

        XCTAssertTrue(
            waitUntil { list.cells.element(boundBy: 0).staticTexts["100%"].exists },
            "Expected Progress to sort the most complete file first")
        XCTAssertTrue(
            waitUntil { sort.title == "Sort by Progress" },
            "Expected the menu to name the active sort, got \(sort.title)")
    }

    /// Clicking a column header quickly must flip the sort on every click.
    /// Clicks inside the double-click interval arrive with a click count of 2,
    /// and AppKit used to route those to the table's `doubleAction` instead of
    /// sorting, so every second fast click did nothing.
    @MainActor
    func testSnapshotHeaderFlipsSortOnEveryFastClick() throws {
        guard let fixture = fixtureURL() else {
            throw XCTSkip("Missing committed snapshot fixture")
        }

        let app = snapshotApp(fixture)
        let table = app.tables["torrents.table"]
        XCTAssertTrue(table.cells.firstMatch.waitForExistence(timeout: 15))
        let header = table.buttons["Size"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        // Click by coordinate. Under the toolbar the header reads as not
        // hittable to XCUITest (AppKit hit-tests it fine), and element clicks
        // then stop behaving like a real double click, hiding the bug.
        let headerPoint = header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let parkPoint = app.windows.firstMatch.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))

        // The sort direction isn't in the accessibility tree, so read the
        // arrow from pixels, with the pointer parked so hover can't differ.
        func arrow() -> Data {
            parkPoint.hover()
            Thread.sleep(forTimeInterval: 0.3)
            return header.screenshot().pngRepresentation
        }
        func topRow() -> String {
            table.cells.element(boundBy: 0).staticTexts.firstMatch.label
        }

        headerPoint.click()
        Thread.sleep(forTimeInterval: 0.6)
        let firstArrow = arrow()
        let firstTop = topRow()

        headerPoint.click()
        Thread.sleep(forTimeInterval: 0.6)
        let secondArrow = arrow()
        let secondTop = topRow()
        XCTAssertNotEqual(secondArrow, firstArrow, "Expected a slow second click to flip the arrow")
        XCTAssertNotEqual(secondTop, firstTop, "Expected a slow second click to re-sort the rows")

        // Two fast clicks flip twice, landing back where they started. With
        // the bug only the first flipped, leaving the first click's state.
        headerPoint.doubleClick()
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(
            topRow(), secondTop, "Expected both clicks of a fast double click to re-sort the rows")
        XCTAssertEqual(
            arrow(), secondArrow, "Expected both clicks of a fast double click to flip the arrow")
    }

    /// Launches the app on the committed snapshot fixture. State restoration is
    /// switched off: a Preferences window left open by an earlier test would
    /// cover the table and make rows unhittable. The window frame is pinned
    /// too, since frame autosave ignores that switch: whatever an earlier
    /// launch saved would otherwise come back.
    private func snapshotApp(_ fixture: URL) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--snapshot", fixture.path, "-ApplePersistenceIgnoreState", "YES",
            "-NSWindow Frame main", "0 63 1000 652 0 0 1024 768",
        ]
        app.launch()
        fitWindowToScreen(app)
        return app
    }

    /// On the CI runners' 1024pt display the toolbar holds the window at about
    /// 1150pt with all three columns, leaving the inspector's right edge
    /// off-screen. Hiding the sidebar lowers that minimum, and Zoom then fits
    /// the window to the screen. The hidden sidebar persists, so later launches
    /// skip this; a display wide enough never gets here.
    private func fitWindowToScreen(_ app: XCUIApplication) {
        let window = app.windows["main"]
        guard window.waitForExistence(timeout: 15), let screen = NSScreen.main,
            window.frame.maxX > screen.frame.maxX
        else { return }
        let sidebar = app.descendants(matching: .any)
            .matching(identifier: "sidebar.status.all").firstMatch
        if sidebar.exists {
            app.typeKey("s", modifierFlags: [.command, .control])
            XCTAssertTrue(waitUntil { !sidebar.exists }, "Expected ⌃⌘S to hide the sidebar")
        }
        let hidden = window.frame
        app.menuBars.firstMatch.menuBarItems["Window"].click()
        app.menuItems["Zoom"].click()
        XCTAssertTrue(
            waitUntil { window.frame.maxX <= screen.frame.maxX },
            "Expected Zoom to fit the window to the screen, got \(window.frame)")
    }

    /// Polls the given condition, keeping menu state assertions honest while
    /// SwiftUI commits the selection change.
    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return condition()
    }

    /// `#filePath`-derived path (repo checkout layout) with a bundled-resource
    /// fallback. The filesystem-synchronized UITests group also copies JSON
    /// into the test bundle's Resources, so both work regardless of checkout
    /// location.
    private func fixtureURL() -> URL? {
        let candidates: [URL?] = [
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/snapshot-10-torrents.json"),
            Bundle(for: Self.self).url(forResource: "snapshot-10-torrents", withExtension: "json"),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
