import Foundation
import Testing

@testable import TransmissionCore

@Suite("GeoIPService")
struct GeoIPServiceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func needs(
        hasFile: Bool = true,
        release: String? = "2026-10",
        frequency: GeoIPRefreshFrequency = .daily,
        success: String? = "2026-10-09T12:00:00Z",
        attempt: String? = "2026-09-01T00:00:00Z",
        current: String = "2026-10",
        now: String = "2026-10-09T12:00:00Z"
    ) -> Bool {
        GeoIPService.needsDownload(
            hasFile: hasFile,
            downloadedRelease: release,
            lastSuccess: success.map { date($0) },
            lastAttempt: attempt.map { date($0) },
            currentMonth: current,
            frequency: frequency,
            now: date(now),
            calendar: calendar
        )
    }

    @Test func noCacheIsDue() {
        #expect(needs(hasFile: false, release: nil, success: nil, attempt: nil))
    }

    @Test func retryFloorBlocksRapidAttempts() {
        #expect(!needs(attempt: "2026-10-09T11:30:00Z", now: "2026-10-09T12:00:00Z"))
    }

    @Test func pendingReleaseIsDueRegardlessOfFrequency() {
        // Cached file is September's while the current month is October.
        #expect(needs(release: "2026-09", frequency: .monthly, current: "2026-10"))
    }

    @Test func frequencyGateForCurrentRelease() {
        #expect(!needs(frequency: .daily, success: "2026-10-09T08:00:00Z"))
        #expect(needs(frequency: .daily, success: "2026-10-08T08:00:00Z"))
        #expect(!needs(frequency: .weekly, success: "2026-10-07T08:00:00Z"))
        #expect(needs(frequency: .weekly, success: "2026-09-30T08:00:00Z"))
        #expect(!needs(frequency: .monthly, success: "2026-10-01T08:00:00Z"))
        #expect(needs(frequency: .onStartup, success: "2026-10-09T08:00:00Z"))
    }
}
