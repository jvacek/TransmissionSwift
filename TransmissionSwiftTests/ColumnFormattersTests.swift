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

    @Test func ratio_positiveIsTwoDecimals() {
        #expect(ColumnFormatters.ratio(1.755) == "1.75")
        #expect(ColumnFormatters.ratio(0.4) == "0.40")
    }
}
