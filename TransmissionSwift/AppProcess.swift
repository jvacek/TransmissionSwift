import Foundation

/// Process-environment facts the app branches on. Kept in one place so the
/// "don't read the Keychain or show interactive UI under Xcode's test host or
/// SwiftUI previews" rule can't drift between its call sites.
nonisolated enum AppProcess {
    /// True when running as Xcode's test host or preview process.
    static var isXcodeAuxiliary: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}
