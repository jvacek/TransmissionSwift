// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
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

    @Test func parsesCRLFLineEndings() {
        let index = CountryIndex(csv: "1.0.0.0,1.0.0.255,AU\r\n1.0.1.0,1.0.1.255,CN\r\n")
        #expect(index.countryCode(forIPv4: CountryIndex.ipv4("1.0.0.1")!) == "AU")
        #expect(index.countryCode(forIPv4: CountryIndex.ipv4("1.0.1.1")!) == "CN")
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

    @Test func ipv4ParsingRejectsOverlongOctetsWithoutOverflowing() {
        #expect(CountryIndex.ipv4("1.2.3.4294967296") == nil)
        #expect(CountryIndex.ipv4("1.2.3.99999999999999999999") == nil)
        #expect(CountryIndex.ipv4("1.2.3.0000") == nil)
    }

    @Test func normalizesCodesAndDropsMalformedRows() {
        let index = CountryIndex(
            csv: """
                1.0.0.0,1.0.0.255,au
                1.0.1.0,1.0.1.255,AUS
                1.0.2.0,1.0.2.255,
                1.0.3.0,1.0.3.255,ZZ
                """)

        #expect(index.rowCount == 1)
        #expect(index.countryCode(forIPv4: CountryIndex.ipv4("1.0.0.1")!) == "AU")
        #expect(index.countryCode(forIPv4: CountryIndex.ipv4("1.0.1.1")!) == nil)
    }

    @Test func gzipRejectsANonDatabaseFile() throws {
        let index = CountryIndex(gzipAt: try writeTemp(Data("<html>error</html>".utf8)))
        #expect(index == nil)
    }

    @Test func gzipRejectsATruncatedStream() throws {
        let gzip = try #require(Data(base64Encoded: auGzipBase64))
        let index = CountryIndex(gzipAt: try writeTemp(gzip.dropLast(8)))
        #expect(index == nil)
    }

    @Test func gzipReadsTheRowsAndExposesTheirCount() throws {
        let url = try writeTemp(Data(base64Encoded: auGzipBase64)!)
        let index = try #require(CountryIndex(gzipAt: url))
        #expect(index.rowCount == 1)
        #expect(index.countryCode(forIPv4: CountryIndex.ipv4("1.0.0.1")!) == "AU")
    }

    /// One-row gzip of `1.0.0.0,1.0.0.255,AU`.
    private let auGzipBase64 = "H4sIAAAAAAACAzPUMwBBHUMwbWRqquMYygUA97XRexUAAAA="

    private func writeTemp(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("country-index-\(UUID().uuidString).gz")
        try data.write(to: url)
        return url
    }
}
