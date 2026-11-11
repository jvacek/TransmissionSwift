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

    @Test func nilWhenLettersAreMixedWithOtherCharacters() {
        #expect(countryFlagEmoji(for: "N1L") == nil)
        #expect(countryFlagEmoji(for: "U.S") == nil)
        // Uppercasing "ß" expands it to "SS", which is a real code.
        #expect(countryFlagEmoji(for: "ß") == nil)
    }
}
