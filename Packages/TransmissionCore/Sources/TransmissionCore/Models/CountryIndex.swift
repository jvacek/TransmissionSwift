import CZlib
import Foundation

/// Sorted IPv4 → ISO-3166 country lookup, built from a DB-IP "IP to Country
/// Lite" CSV dump (`start_ip,end_ip,ISO2`). IPv6 ranges and unknown entries
/// (code `ZZ`) are dropped; a miss returns `nil`.
///
/// The dump lists the IPv4 block first, in ascending start-IP order, so
/// appending rows preserves the order the binary search needs.
public struct CountryIndex: Sendable {
    private var starts: [UInt32] = []
    private var ends: [UInt32] = []
    private var countryCodes: [String] = []
    private var rowCode: [UInt16] = []
    private var codeIndex: [String: UInt16] = [:]

    public init() {}

    public init(csv: String) {
        for line in csv.split(whereSeparator: \.isNewline) {
            appendRow(line)
        }
        assertOrdering()
    }

    /// Builds the index by streaming a DB-IP gzip dump line by line. The dump is
    /// ~31 MB uncompressed (732k rows); reading it into one `Data` + `String`
    /// first leaves the allocator holding ~90 MB of high-water footprint for the
    /// life of the process, so parse straight out of zlib instead.
    public init?(gzipAt url: URL) {
        guard let file = gzopen(url.path, "rb") else { return nil }
        defer { _ = gzclose(file) }
        // DB-IP's longest row is under 100 bytes. gzgets only truncates a
        // longer line, which then fails to parse — no worse than skipping it.
        var buffer = [CChar](repeating: 0, count: 256)
        while true {
            let read = buffer.withUnsafeMutableBufferPointer { bytes in
                gzgets(file, bytes.baseAddress, Int32(bytes.count))
            }
            guard read != nil else { break }
            appendRow(String(cString: buffer))
        }
        assertOrdering()
    }

    private mutating func appendRow(_ line: some StringProtocol) {
        let fields = line.split(separator: ",", maxSplits: 2)
        guard fields.count == 3,
            let start = Self.ipv4(fields[0]),
            let end = Self.ipv4(fields[1])
        else { return }
        let code = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, code != "ZZ" else { return }
        starts.append(start)
        ends.append(end)
        rowCode.append(intern(code))
    }

    private func assertOrdering() {
        assert(
            zip(starts, starts.dropFirst()).allSatisfy { pair in pair.0 <= pair.1 },
            "GeoIP CSV was not in ascending start-IP order")
    }

    public var isEmpty: Bool { starts.isEmpty }

    public func countryCode(forIPv4 ip: UInt32) -> String? {
        guard !starts.isEmpty else { return nil }
        var low = 0
        var high = starts.count - 1
        while low <= high {
            let mid = low + (high - low) / 2
            if ip < starts[mid] {
                high = mid - 1
            } else if ip > ends[mid] {
                low = mid + 1
            } else {
                return countryCodes[Int(rowCode[mid])]
            }
        }
        return nil
    }

    private mutating func intern(_ code: String) -> UInt16 {
        if let existing = codeIndex[code] { return existing }
        let index = UInt16(countryCodes.count)
        countryCodes.append(code)
        codeIndex[code] = index
        return index
    }

    /// Parses a dotted-quad IPv4 literal to its 32-bit value. Returns nil for
    /// IPv6 literals, hostnames and malformed input.
    public static func ipv4<S: StringProtocol>(_ text: S) -> UInt32? {
        var value: UInt32 = 0
        var octet: UInt32 = 0
        var digits = 0
        var dots = 0
        for character in text {
            if character == "." {
                guard digits > 0, octet <= 255, dots < 3 else { return nil }
                value = (value << 8) | octet
                octet = 0
                digits = 0
                dots += 1
            } else if character.isASCII, let digit = character.wholeNumberValue {
                guard digits < 3 else { return nil }
                octet = octet * 10 + UInt32(digit)
                guard octet <= 255 else { return nil }
                digits += 1
            } else {
                return nil
            }
        }
        guard dots == 3, digits > 0, octet <= 255 else { return nil }
        return (value << 8) | octet
    }
}
