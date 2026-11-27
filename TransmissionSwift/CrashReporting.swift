// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Foundation
import Sentry
import TransmissionCore
import os

private nonisolated let logger = Logger(
    subsystem: "net.jvacek.TransmissionSwift", category: "CrashReporting")

/// Opt-in crash reporting via Sentry.
///
/// The SDK runs only when **both** switches are on:
///
/// 1. A DSN is present. It is injected at build time through the `SENTRY_DSN`
///    build setting, which `Info.plist` expands into the `SentryDSN` key. A
///    DSN is committed for Debug and Release, so every local build is also
///    configured and offers the first-run consent splash; a build whose value
///    is unexpanded or missing leaves the SDK inert.
/// 2. The user enabled "Send anonymous crash reports" (default off).
///
/// Deliberately narrow: no PII and no auto session tracking, so a report can
/// never carry a daemon host, torrent name, or credentials. It does carry load
/// counters (see `trackRuntimeLoad`) — numbers only, enough to tell a slow app
/// from a loaded machine.
enum CrashReporting {
    /// `UserDefaults` key behind the General-pane opt-in toggle.
    nonisolated static let preferenceKey = "sendCrashReports"
    /// Set once the first-run splash is answered, so it shows only on the very
    /// first launch. Presence of the key (not its value) is the signal.
    nonisolated static let consentKey = "crashReportingConsentAnswered"
    /// One-line privacy statement shared by the splash and the settings footer.
    nonisolated static let privacySummary =
        "Reports carry a backtrace, the app version, and load counters: torrent count, CPU and memory use, poll intervals. Never torrent names, tracker hosts, or server addresses."

    /// Whether this build was shipped with a DSN (see `Info.plist`). Without one
    /// there is nothing to report and no reason to ask.
    nonisolated static var isConfigured: Bool { dsn != nil }

    /// True until the first-run splash has been answered.
    nonisolated static var needsConsent: Bool {
        UserDefaults.standard.object(forKey: consentKey) == nil
    }

    /// Records the user's crash-reporting choice and applies it. Called by both
    /// the first-run splash and the settings toggle, and marks the splash
    /// answered either way so it never reappears. Persisted in `UserDefaults`,
    /// so it survives relaunch and both surfaces read the same value.
    nonisolated static func setConsent(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: preferenceKey)
        UserDefaults.standard.set(true, forKey: consentKey)
        apply()
    }

    /// Start or stop the SDK to match the current DSN + preference. Idempotent,
    /// so it doubles as the preference-toggle handler.
    nonisolated static func apply() {
        let enabled = dsn != nil && UserDefaults.standard.bool(forKey: preferenceKey)
        if enabled, !SentrySDK.isEnabled {
            start()
        } else if !enabled, SentrySDK.isEnabled {
            SentrySDK.close()
        }
    }

    #if DEBUG
    /// Verification hooks behind the `--crash-test` launch argument, to prove
    /// the capture → upload → Sentry path end to end without touching the
    /// persisted opt-in. `--crash-test` crashes after startup; `--crash-test-send`
    /// only boots the SDK so a previously captured crash uploads.
    nonisolated static func startForTesting() {
        guard dsn != nil else {
            logger.warning("[Sentry] crash test ignored: this build has no DSN")
            return
        }
        if !SentrySDK.isEnabled { start() }
    }

    nonisolated static func crashForTesting() {
        SentrySDK.crash()
    }
    #endif

    nonisolated private static func start() {
        guard let dsn else { return }
        SentrySDK.start { options in
            options.dsn = dsn
            options.sendDefaultPii = false
            options.enableAutoSessionTracking = false
            // Sentry 9.x defaults both of these ON. Failed-request capture turns
            // any HTTP 5xx (favicon/tracker fetches) into an error event, and
            // network breadcrumbs attach request URLs — both would leak tracker
            // hosts and the daemon address, which `privacySummary` promises we
            // never send. Keep reports to actual crashes only.
            options.enableCaptureFailedRequests = false
            options.enableNetworkTracking = false
            // AppKit rethrows an exception raised in layout as a C++ exception,
            // so without this the report has no NSException name or reason.
            options.enableUncaughtNSExceptionReporting = true
            options.environment = environment
            if let release = releaseName { options.releaseName = release }
        }
    }

    /// A debug build reports into its own Sentry environment, so a developer's
    /// local crashes don't read as shipped ones.
    nonisolated static var environment: String {
        #if DEBUG
        "debug"
        #else
        "release"
        #endif
    }

    /// Sentry's conventional `"<version>+<build>"` release name. A bare build
    /// number would group unrelated versions together.
    nonisolated static var releaseName: String? {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else { return nil }
        guard let build = info?["CFBundleVersion"] as? String else { return version }
        return "\(version)+\(build)"
    }

    /// The configured DSN, or `nil` when the build carries none. Rejects an
    /// unexpanded `$(SENTRY_DSN)` literal so it can't masquerade as a DSN.
    nonisolated private static var dsn: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
            value.contains("://")
        else { return nil }
        return value
    }

    // MARK: - Load context

    /// Context key the sampler writes; the event detail shows it as a section.
    nonisolated static let loadContextKey = "app.load"

    /// Feeds an `app.load` context to every event, so an app-hang report says
    /// whether the library was big, the app was burning CPU, or the machine was
    /// already loaded. Sentry reports the app footprint and the free system
    /// memory itself, but "free memory" on macOS reads as alarm at any time, so
    /// pressure is expressed here as used-percent plus compression.
    ///
    /// Values are up to one sample interval (5 s) old: the loop cannot run while
    /// the main thread is hung, which is the condition it exists to describe.
    /// `torrents` is a caller-supplied read rather than an observation, because
    /// reading the list inside a `body` would invalidate the root view on every
    /// poll.
    @MainActor
    static func trackRuntimeLoad(torrents: @escaping @MainActor () -> Int) {
        guard isConfigured, !AppProcess.isXcodeAuxiliary, loadTask == nil else { return }
        loadTask = Task { @MainActor in
            var previous = ProcessMetrics.sample()
            var sampledAt = DispatchTime.now().uptimeNanoseconds
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let current = ProcessMetrics.sample() else { continue }
                let now = DispatchTime.now().uptimeNanoseconds
                let elapsed = Double(now &- sampledAt) / 1_000_000_000
                let spent = current.cpuSeconds - (previous?.cpuSeconds ?? current.cpuSeconds)
                previous = current
                sampledAt = now
                guard SentrySDK.isEnabled else { continue }
                let load = RuntimeLoad(
                    torrents: torrents(),
                    cpuPercent: elapsed > 0 ? max(0, spent / elapsed * 100) : 0,
                    memoryUsedPercent: current.memoryUsedPercent,
                    compressedMB: current.compressedBytes / 1_048_576,
                    loadAverage1m: current.loadAverage1m,
                    refreshInterval: storedInterval(
                        PreferenceKeys.pollingIntervalSeconds,
                        fallback: PollingIntervals.defaultRefresh),
                    incrementalInterval: storedInterval(
                        PreferenceKeys.incrementalPollingIntervalSeconds,
                        fallback: PollingIntervals.defaultIncremental),
                    isActive: NSApplication.shared.isActive,
                    windowVisible: NSApplication.shared.occlusionState.contains(.visible))
                SentrySDK.configureScope { scope in
                    scope.setContext(value: load.context, key: loadContextKey)
                }
            }
        }
    }

    @MainActor private static var loadTask: Task<Void, Never>?

    nonisolated private static func storedInterval(_ key: String, fallback: Double) -> Double {
        let value = UserDefaults.standard.double(forKey: key)
        return value > 0 ? value : fallback
    }
}

/// One `app.load` context. Scalars only, so nothing here can carry a torrent
/// name or a daemon address.
nonisolated struct RuntimeLoad {
    var torrents: Int
    var cpuPercent: Double
    var memoryUsedPercent: Double
    var compressedMB: Double
    var loadAverage1m: Double
    var refreshInterval: Double
    var incrementalInterval: Double
    var isActive: Bool
    var windowVisible: Bool

    var context: [String: Any] {
        [
            "torrents": torrents,
            "cpu_percent": (cpuPercent * 10).rounded() / 10,
            "memory_used_percent": (memoryUsedPercent * 10).rounded() / 10,
            "compressed_mb": (compressedMB * 10).rounded() / 10,
            "load_average_1m": (loadAverage1m * 100).rounded() / 100,
            "poll_refresh_s": refreshInterval,
            "poll_incremental_s": incrementalInterval,
            "app_active": isActive,
            "window_visible": windowVisible,
        ]
    }
}

/// One kernel sample of the process and the machine. `nil` when either call
/// fails, so a report never carries a fabricated zero.
nonisolated struct ProcessMetrics {
    /// CPU seconds this process has burned since launch, all threads.
    var cpuSeconds: Double
    /// Active + wired + compressed pages as a share of physical memory. Unlike
    /// `free_memory` this does not read as full on a healthy Mac.
    var memoryUsedPercent: Double
    var compressedBytes: Double
    var loadAverage1m: Double

    static func sample() -> ProcessMetrics? {
        var task = mach_task_basic_info()
        var taskCount = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let taskResult = withUnsafeMutablePointer(to: &task) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(taskCount)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &taskCount)
            }
        }

        var stats = vm_statistics64()
        var statsCount = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let hostResult = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(statsCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &statsCount)
            }
        }

        guard taskResult == KERN_SUCCESS, hostResult == KERN_SUCCESS else { return nil }

        let pageSize = Double(sysconf(_SC_PAGESIZE))
        let compressed = Double(stats.compressor_page_count) * pageSize
        let used = (Double(stats.active_count) + Double(stats.wire_count)) * pageSize + compressed
        let physical = Double(ProcessInfo.processInfo.physicalMemory)

        var loadAverage = [Double](repeating: 0, count: 3)
        let loadCount = getloadavg(&loadAverage, 3)

        return ProcessMetrics(
            cpuSeconds: Double(task.user_time.seconds) + Double(task.user_time.microseconds) / 1e6
                + Double(task.system_time.seconds) + Double(task.system_time.microseconds) / 1e6,
            memoryUsedPercent: physical > 0 ? min(100, used / physical * 100) : 0,
            compressedBytes: compressed,
            loadAverage1m: loadCount > 0 ? loadAverage[0] : 0)
    }
}
