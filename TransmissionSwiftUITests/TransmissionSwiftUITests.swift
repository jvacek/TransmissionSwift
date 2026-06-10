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
}
