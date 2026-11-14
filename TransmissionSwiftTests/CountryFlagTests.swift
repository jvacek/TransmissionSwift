// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
import TransmissionCore

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

/// The Peers tab folds client and flags into one secondary line under the
/// address; a missing half must not leave a dangling separator.
@Suite("Peer detail line")
struct PeerDetailLineTests {
    private func peer(client: String, flags: String) -> Peer {
        Peer(
            ipAddress: "203.0.113.42", client: client, flags: flags, progress: 0.5,
            downloadSpeed: 0, uploadSpeed: 0)
    }

    @Test func joinsClientAndFlags() {
        #expect(InspectorPeersTab.detail(for: peer(client: "Deluge 2.1.1", flags: "UDe")) == "Deluge 2.1.1 · UDe")
    }

    @Test func dropsTheMissingHalf() {
        #expect(InspectorPeersTab.detail(for: peer(client: "Deluge 2.1.1", flags: "")) == "Deluge 2.1.1")
        #expect(InspectorPeersTab.detail(for: peer(client: "", flags: "UDe")) == "UDe")
        #expect(InspectorPeersTab.detail(for: peer(client: "", flags: "")).isEmpty)
    }
}
