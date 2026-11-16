// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Preflight for the opt-in App Intents UI tests. Xcode's AppIntentsTesting is a
// host tool: it must resolve against the installed macOS AppIntentsTypeSupport.
// A mismatched Xcode/macOS pair fails at bundle load with a missing-symbol
// error, which used to take the whole UI test bundle down with it. Load it with
// RTLD_NOW here so the dedicated lane fails fast and clearly instead.

import Darwin
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let developerDir: String
if let fromEnvironment = ProcessInfo.processInfo.environment["DEVELOPER_DIR"],
    !fromEnvironment.isEmpty
{
    developerDir = fromEnvironment
} else {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    process.arguments = ["-p"]
    let pipe = Pipe()
    process.standardOutput = pipe
    do {
        try process.run()
    } catch {
        fail("Could not run xcode-select: \(error.localizedDescription)")
    }
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    developerDir = String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

let framework =
    developerDir
    + "/Platforms/MacOSX.platform/Developer/Library/Frameworks/"
    + "AppIntentsTesting.framework/Versions/A/AppIntentsTesting"

guard FileManager.default.fileExists(atPath: framework) else {
    fail(
        """
        AppIntentsTesting was not found at \(framework).
        App Intents UI tests need Xcode 27 or newer. The main UI suite does not.
        """)
}

guard let handle = dlopen(framework, RTLD_NOW) else {
    let detail = dlerror().map { String(cString: $0) } ?? "unknown loader error"
    fail(
        """
        App Intents UI tests cannot load AppIntentsTesting on this machine:
        \(detail)

        The main UI suite does not need this framework. Use an Xcode/macOS pair
        where AppIntentsTesting loads, or run `just test-snapshot`.
        """)
}
dlclose(handle)
print("AppIntentsTesting loads.")
