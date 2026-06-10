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

    /// `--mock-data` shows the S1 main window backed by `MockFixtures`.
    /// 10 torrents → sidebar's All Torrents row carries value "10" and the
    /// status bar reports the same count.
    @MainActor
    func testMockDataMainWindow() {
        let app = XCUIApplication()
        app.launchArguments = ["--mock-data", "--ephemeral-profiles"]
        app.launch()

        // SwiftUI's NavigationSplitView + toolbar takes ~3s after launch to
        // wire its accessibility tree. 10s gives headroom.
        let allTorrents = app.staticTexts["sidebar.status.all"]
        XCTAssertTrue(
            allTorrents.waitForExistence(timeout: 10),
            "Expected the sidebar's 'All Torrents' row to render")
        XCTAssertEqual(allTorrents.value as? String, "10")

        let downloading = app.staticTexts["sidebar.status.downloading"]
        XCTAssertTrue(downloading.waitForExistence(timeout: 5))
        XCTAssertEqual(downloading.value as? String, "3")

        let table = app.outlines["torrents.table"]
        XCTAssertTrue(
            table.waitForExistence(timeout: 5),
            "Expected the torrent table to render")
    }

    /// Slice 2: select the Debian fixture (rich files/peers/trackers), then
    /// walk all five inspector tabs and assert each renders its key content.
    @MainActor
    func testInspectorTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["--mock-data", "--ephemeral-profiles"]
        app.launch()

        let table = app.outlines["torrents.table"]
        XCTAssertTrue(table.waitForExistence(timeout: 10))

        let debianRow = table.staticTexts["Debian 12.6 — netinst (multi-arch) collection"]
        XCTAssertTrue(debianRow.waitForExistence(timeout: 5))
        debianRow.click()

        // General is the default tab.
        XCTAssertTrue(
            app.staticTexts["Transfer"].waitForExistence(timeout: 5),
            "Expected the General tab's Transfer section")
        XCTAssertTrue(app.staticTexts["Time left"].exists)

        selectInspectorTab(app, "Files")
        XCTAssertTrue(
            app.staticTexts["debian-12.6.0-amd64-netinst.iso"].waitForExistence(timeout: 5),
            "Expected the Files tab to list the Debian payload")

        selectInspectorTab(app, "Peers")
        XCTAssertTrue(
            app.staticTexts["94.142.241.111"].waitForExistence(timeout: 5),
            "Expected the Peers tab to list the NL peer")

        selectInspectorTab(app, "Trackers")
        XCTAssertTrue(
            app.staticTexts["open.tracker.cl"].waitForExistence(timeout: 5),
            "Expected the Trackers tab to show the tier-2 tracker")

        selectInspectorTab(app, "Options")
        XCTAssertTrue(
            app.staticTexts["Bandwidth"].waitForExistence(timeout: 5),
            "Expected the Options tab's Bandwidth section")
    }

    /// The inspector's segmented tab control. NSSegmentedControl exposes its
    /// segments as radio buttons in the AX tree; fall back to plain buttons
    /// in case the representation shifts between macOS releases.
    private func selectInspectorTab(_ app: XCUIApplication, _ label: String) {
        let radio = app.radioButtons[label]
        if radio.waitForExistence(timeout: 2) {
            radio.click()
            return
        }
        app.buttons[label].firstMatch.click()
    }
}
