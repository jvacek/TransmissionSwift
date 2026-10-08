import AppKit
import Foundation
import Sparkle
import TransmissionCore

final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    private static let arm64FeedURL = "https://jvacek.github.io/TransmissionSwift/appcast-arm64.xml"

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UserDefaults.standard.bool(forKey: PreferenceKeys.includePrereleases) ? ["beta"] : []
    }

    // Apple Silicon gets the arm64-only feed (smaller updates). Intel Macs
    // fall back to SUFeedURL, which serves the universal build.
    func feedURLString(for updater: SPUUpdater) -> String? {
        Self.isAppleSilicon ? Self.arm64FeedURL : nil
    }

    // Mirrors Sparkle's own arm64 hardware check: true on Apple Silicon
    // including a Rosetta-translated process, false on a native Intel Mac.
    private static var isAppleSilicon: Bool {
        #if arch(x86_64)
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 else {
            return false
        }
        return translated == 1
        #else
        return true
        #endif
    }
}

final class UpdateService {
    let controller: SPUStandardUpdaterController
    private let delegate = UpdaterDelegate()

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
    }

    @objc func checkForUpdates(_ sender: Any?) {
        controller.checkForUpdates(sender)
    }
}
