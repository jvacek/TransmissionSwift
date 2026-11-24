// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import TransmissionSwift

/// The first-run splash decides "shown yet?" by the *presence* of a defaults
/// key, not its value (`sendCrashReports` defaults to false and can't tell
/// "not asked" from "declined"). Guard that contract, and that the answer the
/// splash records is the same key the settings toggle reads.
///
/// Serialized: it mutates `UserDefaults.standard`, so it must not race the
/// other app tests (or itself) while the keys are briefly shifted.
@Suite(.serialized)
struct CrashReportingTests {
    @Test func consentRoundTripPersistsChoice() {
        let defaults = UserDefaults.standard
        let savedConsent = defaults.object(forKey: CrashReporting.consentKey)
        let savedChoice = defaults.object(forKey: CrashReporting.preferenceKey)
        defer {
            restore(defaults, key: CrashReporting.consentKey, value: savedConsent)
            restore(defaults, key: CrashReporting.preferenceKey, value: savedChoice)
        }

        defaults.removeObject(forKey: CrashReporting.consentKey)
        #expect(CrashReporting.needsConsent)

        CrashReporting.setConsent(enabled: true)
        #expect(!CrashReporting.needsConsent)
        #expect(defaults.bool(forKey: CrashReporting.preferenceKey))

        // Declining also records the answer, so the splash never reappears.
        CrashReporting.setConsent(enabled: false)
        #expect(!CrashReporting.needsConsent)
        #expect(!defaults.bool(forKey: CrashReporting.preferenceKey))
    }

    /// Sentry groups events by release and environment, so both must carry the
    /// full version and a build-config tag rather than a bare build number.
    @Test func releaseNameAndEnvironmentTagTheBuild() throws {
        let release = try #require(CrashReporting.releaseName)
        #expect(release.contains("+"), "Expected version+build, got \(release)")
        #expect(CrashReporting.environment == "debug")
    }

    /// The context is the only place a hang's environment is visible, so the
    /// mach calls behind it must return real numbers rather than defaults.
    @Test func loadSampleReadsRealNumbers() throws {
        let metrics = try #require(ProcessMetrics.sample())
        #expect(metrics.cpuSeconds >= 0)
        #expect(metrics.memoryUsedPercent > 0 && metrics.memoryUsedPercent <= 100)
        #expect(metrics.compressedBytes >= 0)
        #expect(metrics.loadAverage1m >= 0)
    }

    /// The event context is a flat dictionary of scalars, and every key is one
    /// the hang triage relies on. A string or nested value here would be a PII
    /// leak vector, so keep the shape pinned.
    @Test func loadContextIsFlatScalars() {
        let load = RuntimeLoad(
            torrents: 120, cpuPercent: 3.44, memoryUsedPercent: 61.5, compressedMB: 812.3,
            loadAverage1m: 1.237, refreshInterval: 15, incrementalInterval: 1,
            isActive: true, windowVisible: false)
        let context = load.context

        #expect(context["torrents"] as? Int == 120)
        #expect(context["cpu_percent"] as? Double == 3.4)
        #expect(context["memory_used_percent"] as? Double == 61.5)
        #expect(context["compressed_mb"] as? Double == 812.3)
        #expect(context["load_average_1m"] as? Double == 1.24)
        #expect(context["poll_refresh_s"] as? Double == 15)
        #expect(context["poll_incremental_s"] as? Double == 1)
        #expect(context["app_active"] as? Bool == true)
        #expect(context["window_visible"] as? Bool == false)
        #expect(context.values.allSatisfy { $0 is Int || $0 is Double || $0 is Bool })
    }

    private func restore(_ defaults: UserDefaults, key: String, value: Any?) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
