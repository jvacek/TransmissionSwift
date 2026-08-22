//
//  TransmissionSwiftUITests.swift
//  TransmissionSwiftUITests
//
//  Created by Jonas Vacek on 10/06/2026.
//

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
            ProcessInfo.processInfo.environment["TEST_RUNNER_TRANSMISSION_E2E"] == "1",
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
    /// nstableview-migration) renders rows. Boots the app on a committed,
    /// anonymized snapshot fixture so the test runs anywhere — CI included —
    /// with no daemon and no dependence on the developer's ~/Downloads.
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

        // The fixture's first torrent must have decoded through the wire mapping.
        let firstRow = table.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Sample Archive 01")
        ).firstMatch
        XCTAssertTrue(
            firstRow.waitForExistence(timeout: 5),
            "Expected a known fixture torrent name to render")
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
