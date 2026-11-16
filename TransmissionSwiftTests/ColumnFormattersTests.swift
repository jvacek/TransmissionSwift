// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

@testable import TransmissionSwift

/// The column formatters that feed the native cells.
@Suite("ColumnFormatters")
struct ColumnFormattersTests {
    @Test func speedParts_splitsValueAndUnit() {
        #expect(ColumnFormatters.speedParts(1024) == ("1.0", "KB/s"))
        #expect(ColumnFormatters.speedParts(2_300_000) == ("2.2", "MB/s"))
        #expect(ColumnFormatters.speedParts(500) == ("500.0", "B/s"))
    }

    @Test func speedParts_zeroIsEmDash() {
        // Zero renders as a dash with no unit; the split must not invent one.
        #expect(ColumnFormatters.speedParts(0) == ("\u{2014}", ""))
    }

    @Test func ratio_zeroAndNegativeAreEmDash() {
        // TR_RATIO_NA (-1) / TR_RATIO_INF (-2) clamp to 0 in the model; the
        // formatter must render both, plus a genuine 0, as an em dash.
        #expect(ColumnFormatters.ratio(0) == "\u{2014}")
        #expect(ColumnFormatters.ratio(-1) == "\u{2014}")
        #expect(ColumnFormatters.ratio(-2) == "\u{2014}")
    }

    @Test func lastActivity_nilIsEmDash() {
        #expect(ColumnFormatters.lastActivity(nil) == "\u{2014}")
    }

    @Test func lastActivity_underAMinuteIsJustNow() {
        // Each incremental poll moves activityDate by a second; the text must not.
        let now = Date()
        #expect(ColumnFormatters.lastActivity(now, now: now) == "Just now")
        #expect(ColumnFormatters.lastActivity(now.addingTimeInterval(-1), now: now) == "Just now")
        #expect(ColumnFormatters.lastActivity(now.addingTimeInterval(-59), now: now) == "Just now")
    }

    @Test func lastActivity_daemonClockAheadIsJustNow() {
        // activityDate comes from the daemon's clock; a skew must not read "in 2 sec.".
        let now = Date()
        #expect(ColumnFormatters.lastActivity(now.addingTimeInterval(2), now: now) == "Just now")
    }

    @Test func lastActivity_olderUsesRelativeStyle() {
        let date = Date().addingTimeInterval(-3600)
        #expect(ColumnFormatters.lastActivity(date) == date.formatted(.relative(presentation: .named)))
    }

    @Test func ratio_positiveIsTwoDecimals() {
        #expect(ColumnFormatters.ratio(1.755) == "1.75")
        #expect(ColumnFormatters.ratio(0.4) == "0.40")
    }
}
