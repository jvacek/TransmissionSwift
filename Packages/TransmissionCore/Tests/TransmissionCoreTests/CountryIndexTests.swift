import Testing

@testable import TransmissionCore

@Suite("CountryIndex")
struct CountryIndexTests {
    private let csv = """
        1.0.0.0,1.0.0.255,AU
        1.0.1.0,1.0.3.255,CN
        2.0.0.0,2.255.255.255,ZZ
        2001:200::,2001:200:ffff:ffff:ffff:ffff:ffff:ffff,JP
        """

    @Test func lookupHitsRangesAndMissesGaps() {
        let index = CountryIndex(csv: csv)
        #expect(index.countryCode(forIPv4: CountryIndex.ipv4("1.0.0.1")!) == "AU")
        #expect(index.countryCode(forIPv4: CountryIndex.ipv4("1.0.3.255")!) == "CN")
        // A hole between ranges.
        #expect(index.countryCode(forIPv4: CountryIndex.ipv4("1.0.4.0")!) == nil)
        // `ZZ` (unknown) rows are dropped.
        #expect(index.countryCode(forIPv4: CountryIndex.ipv4("2.1.1.1")!) == nil)
    }

    @Test func ipv4ParsingRejectsNonIPv4() {
        #expect(CountryIndex.ipv4("192.168.1.1") == 0xC0A8_0101)
        #expect(CountryIndex.ipv4("255.255.255.255") == 0xFFFF_FFFF)
        #expect(CountryIndex.ipv4("0.0.0.0") == 0)
        #expect(CountryIndex.ipv4("1.2.3") == nil)
        #expect(CountryIndex.ipv4("1.2.3.4.5") == nil)
        #expect(CountryIndex.ipv4("1.2.3.256") == nil)
        #expect(CountryIndex.ipv4("2001:db8::1") == nil)
        #expect(CountryIndex.ipv4("") == nil)
    }
}
