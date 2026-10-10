import Testing

@testable import TransmissionSwift

@Suite("CountryFlag")
struct CountryFlagTests {
    @Test func emojiForKnownCodes() {
        #expect(countryFlagEmoji(for: "NL") == "🇳🇱")
        #expect(countryFlagEmoji(for: "us") == "🇺🇸")
    }

    @Test func nilForMalformedCodes() {
        #expect(countryFlagEmoji(for: "N") == nil)
        #expect(countryFlagEmoji(for: "NLD") == nil)
        #expect(countryFlagEmoji(for: "12") == nil)
        #expect(countryFlagEmoji(for: "") == nil)
    }
}
