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

        let app = XCUIApplication()
        app.launchArguments = ["--snapshot", fixture.path]
        app.launch()

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
        let savedItems = pasteboard.pasteboardItems
        defer {
            pasteboard.clearContents()
            if let savedItems { pasteboard.writeObjects(savedItems) }
        }

        let app = XCUIApplication()
        app.launchArguments = ["--snapshot", fixture.path]
        app.launch()

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
        let savedItems = pasteboard.pasteboardItems
        defer {
            pasteboard.clearContents()
            if let savedItems { pasteboard.writeObjects(savedItems) }
        }

        let app = XCUIApplication()
        app.launchArguments = ["--snapshot", fixture.path]
        app.launch()

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

        let inspector = app.descendants(matching: .any)
            .matching(identifier: "inspector.tabs").firstMatch
        let inspectorWasVisible = inspector.exists
        app.typeKey("i", modifierFlags: .command)
        XCTAssertTrue(waitUntil { inspector.exists != inspectorWasVisible })
        app.typeKey("i", modifierFlags: .command)
        XCTAssertTrue(waitUntil { inspector.exists == inspectorWasVisible })

        let sidebar = app.descendants(matching: .any)
            .matching(identifier: "sidebar.status.all").firstMatch
        let sidebarWasVisible = sidebar.exists
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(waitUntil { sidebar.exists != sidebarWasVisible })
        app.typeKey("s", modifierFlags: [.command, .control])
        XCTAssertTrue(waitUntil { sidebar.exists == sidebarWasVisible })
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
