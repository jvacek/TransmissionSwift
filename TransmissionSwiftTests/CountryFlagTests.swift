// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

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
