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
    /// nstableview-migration) renders rows. Uses a captured snapshot because the
    /// app has no `--mock-data` launch flag since commit 6a14e0b — the sandbox
    /// grants read access to ~/Downloads so snapshots live there.
    /// Skips when no snapshot is present (CI without a local capture).
    @MainActor
    func testMockDataMainWindow() throws {
        // The real user's Downloads, not the test runner's sandboxed home — the runner
        // resolves NSHomeDirectory() to its own container, but the app-under-test
        // reads ~/Downloads via the sandbox entitlement. NSUserName() is
        // container-agnostic.
        let snapshots = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Users/\(NSUserName())/Downloads/", isDirectory: true),
            includingPropertiesForKeys: [.fileSizeKey]
        )
        .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("snapshot-") }
        // Prefer a small snapshot: AX queries on the 1098-row capture stall
        // (~30s per snapshot, connection loss) and make this test unusable.
        .sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
            let r = (try? rhs.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? .max
            return l < r
        }
        guard let snapshot = snapshots.first else {
            throw XCTSkip("No snapshot-*.json in ~/Downloads to render the table")
        }

        let app = XCUIApplication()
        app.launchArguments = ["--snapshot", snapshot.path]
        app.launch()

        let table = app.tables["torrents.table"]
        XCTAssertTrue(
            table.waitForExistence(timeout: 15),
            "Expected the torrents table to appear in the main window")
        XCTAssertTrue(
            table.cells.firstMatch.waitForExistence(timeout: 10),
            "Expected snapshot data to populate at least one table row")
    }
}
