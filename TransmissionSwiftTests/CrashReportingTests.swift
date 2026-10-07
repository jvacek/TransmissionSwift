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

    private func restore(_ defaults: UserDefaults, key: String, value: Any?) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
