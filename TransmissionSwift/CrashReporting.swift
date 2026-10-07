import Foundation
import Sentry

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
/// never carry a daemon host, torrent name, or credentials.
enum CrashReporting {
    /// `UserDefaults` key behind the General-pane opt-in toggle.
    nonisolated static let preferenceKey = "sendCrashReports"
    /// Set once the first-run splash is answered, so it shows only on the very
    /// first launch. Presence of the key (not its value) is the signal.
    nonisolated static let consentKey = "crashReportingConsentAnswered"
    /// One-line privacy statement shared by the splash and the settings footer.
    nonisolated static let privacySummary =
        "Reports carry a backtrace and the app version — never torrent names, tracker hosts, or server addresses."

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
            NSLog("[Sentry] crash test ignored: this build has no DSN")
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
        let release = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
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
            if let release { options.releaseName = release }
        }
    }

    /// The configured DSN, or `nil` when the build carries none. Rejects an
    /// unexpanded `$(SENTRY_DSN)` literal so it can't masquerade as a DSN.
    nonisolated private static var dsn: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
            value.contains("://")
        else { return nil }
        return value
    }
}
