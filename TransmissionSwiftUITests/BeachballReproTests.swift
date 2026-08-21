import AppKit
import XCTest

/// Deterministic repro of the small→large filter beachball.
///
/// Launches the app replaying a captured snapshot (1098 torrents), narrows the
/// list to a single row ("Downloading"), then expands to "All". The 1098-row
/// re-render hangs the main thread. While the `all.click()` blocks waiting for
/// the app to idle again, a detached task runs `sample` against the app's own
/// PID and writes the stack capture to /tmp/tswift-hang.txt.
final class BeachballReproTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFilterExpandSmallToLargeCapturesSample() throws {
        let snapshotPath = "/Users/jvacek/Downloads/snapshot-2026-08-21-172056.json"
        let samplePath = "/tmp/tswift-hang.txt"
        try? FileManager.default.removeItem(atPath: samplePath)

        let app = XCUIApplication()
        app.launchArguments = ["--snapshot", snapshotPath]
        app.launch()

        // Narrow filter first: "Downloading" matches 1 torrent in this snapshot.
        let downloading = app.descendants(matching: .any)["sidebar.status.downloading"]
        XCTAssertTrue(downloading.waitForExistence(timeout: 15), "sidebar status rows should appear")
        downloading.click()

        // Self-contained capture: sample the app's main thread while the click
        // below blocks on the (hung) 1098-row re-render.
        guard
            let pid = NSRunningApplication.runningApplications(
                withBundleIdentifier: "jvacek.TransmissionSwift"
            ).last?.processIdentifier
        else {
            XCTFail("could not resolve app PID")
            return
        }

        // Marker for external (bash-side) sampling coordination: written right
        // before the big jump so a sampler knows exactly when to capture.
        try? "#trigger".write(
            toFile: "/tmp/tswift-hang-trigger", atomically: true, encoding: .utf8)

        // In-test sample attempt (may be blocked by the test runner's sandbox).
        let capture = Task.detached {
            Thread.sleep(forTimeInterval: 0.2)
            let errPath = "/tmp/tswift-sample-err.log"
            FileManager.default.createFile(atPath: errPath, contents: nil)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
            process.arguments = [String(pid), "12", "-file", "/tmp/tswift-hang.txt", "-mayDie"]
            process.standardError = FileHandle(forWritingAtPath: errPath) ?? FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                print("in-test sample exited: \(process.terminationStatus)")
            } catch {
                print("sample failed: \(error)")
            }
        }

        // Big jump: "All" = 1098 rows. This click blocks until the app idles
        // again, which won't happen while it is beachballing.
        let all = app.descendants(matching: .any)["sidebar.status.all"]
        all.click()

        capture.cancel()
        let exists = FileManager.default.fileExists(atPath: samplePath)
        print("capture file exists: \(exists)")
    }
}
