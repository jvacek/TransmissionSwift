import Foundation
import TransmissionRPC

/// Deterministically redacts a raw snapshot into an anonymized one.
///
/// Operates on the JSON tree produced by re-encoding the raw `SnapshotFile`,
/// keying rules off JSON field names (suffix matching, case-insensitive) so the
/// rules survive new daemon fields without code changes. Every transform is
/// seeded by the original value (FNV-1a + splitmix64), so:
/// - re-running on the same state produces the same output,
/// - the same real tracker / IP / name always maps to the same fake,
/// - fuzzing preserves UI shape: lengths, extensions, separators, and the
///   digit/letter class of each character.
public struct SnapshotRedactor {
    public let options: SnapshotRedactionOptions

    /// Mutable walk state. A class (not struct mutation) so the walk methods
    /// stay non-mutating — the free-text scrub calls into `fakeHost(for:)` from
    /// inside a closure.
    private final class State {
        /// Original tracker host -> fake host, assigned in order of first
        /// appearance so the mapping is stable across runs.
        var hostMap: [String: String] = [:]
        var nextHostIndex = 0
        /// Constant offset applied to every positive unix timestamp so relative
        /// labels ("announced 2m ago") stay correct while absolute times are
        /// hidden.
        var timestampShift: Int64 = 0
    }

    private let state = State()

    public init(options: SnapshotRedactionOptions = SnapshotRedactionOptions()) {
        self.options = options
    }

    /// Redacts a raw snapshot and returns the redacted JSON tree (with a
    /// `redactions` summary embedded) plus the summary itself.
    public func redact(_ raw: SnapshotFile) throws -> (
        tree: [String: Any], summary: SnapshotRedactionSummary
    ) {
        // Anchor: the earliest addedDate maps to 2026-01-01T00:00:00Z.
        let minAdded = raw.torrents.map(\.addedDate).filter { $0 > 0 }.min() ?? 0
        let anchor: Int64 = 1_767_225_600
        state.timestampShift = minAdded > 0 ? anchor - minAdded : 0

        let data = try JSONEncoder().encode(raw)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SnapshotError.malformed("raw snapshot did not serialize to a JSON object")
        }

        var summary = SnapshotRedactionSummary()
        guard let tree = redactValue(object, key: "root", summary: &summary) as? [String: Any] else {
            throw SnapshotError.malformed("redacted snapshot lost its root object")
        }

        var redacted = tree
        redacted["redactions"] = try encodeToTree(summary)
        if var source = redacted["source"] as? [String: Any] {
            source["redacted"] = true
            redacted["source"] = source
        }
        return (redacted, summary)
    }

    // MARK: - Tree walk

    private func redactValue(_ value: Any, key: String, summary: inout SnapshotRedactionSummary) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            // Sorted key order: NSDictionary enumeration order is not stable
            // across runs, which would scramble the first-appearance host
            // mapping and break byte-determinism.
            for childKey in dict.keys.sorted() {
                out[childKey] = redactValue(dict[childKey]!, key: childKey, summary: &summary)
            }
            return out
        }
        if let array = value as? [Any] {
            return array.map { redactValue($0, key: key, summary: &summary) }
        }
        if let string = value as? String {
            return redactString(string, key: key, summary: &summary)
        }
        if let number = value as? NSNumber, isTimestampKey(key), !options.preserveTimestamps,
            number.doubleValue > 0
        {
            // Preserve the numeric type the daemon used (integers stay integers
            // so the file decodes exactly like a live poll).
            if CFNumberIsFloatType(number) {
                let shifted = number.doubleValue + Double(state.timestampShift)
                if shifted != number.doubleValue { summary.timestampsShifted = true }
                return shifted
            }
            let shifted = number.int64Value + state.timestampShift
            if shifted != number.int64Value { summary.timestampsShifted = true }
            return shifted
        }
        return value
    }

    private func redactString(_ string: String, key: String, summary: inout SnapshotRedactionSummary)
        -> String
    {
        let lower = key.lowercased()
        // Exception: peer client names are software identifiers ("Transmission
        // 4.0.6"), not identity — and they'd otherwise match the `name` rule.
        if lower == "clientname" { return string }

        if lower.hasSuffix("announce") || lower.hasSuffix("scrape") || lower.hasSuffix("url") {
            let (rewritten, passkeys) = rewriteTrackerURL(string)
            if options.anonymizeTrackers { summary.trackerURLs += 1 }
            if passkeys > 0 { summary.passkeysStripped += passkeys }
            return rewritten
        }
        if lower.hasSuffix("host") {
            if options.anonymizeTrackers {
                summary.trackerURLs += 1
                return string.contains("://") ? rewriteTrackerURL(string).0 : fakeHost(for: string)
            }
            // Host kept real — but passkeys are never optional, so full URLs
            // still get their query / passkey path stripped.
            return string.contains("://") ? rewriteTrackerURL(string).0 : string
        }
        if lower.hasSuffix("address") {
            summary.peerIPs += 1
            return rewritePeerAddress(string)
        }
        if lower == "labels" {
            if options.includeNames { return string }
            summary.names += 1
            return fuzzName(string)
        }
        if lower == "sitename" {
            if options.anonymizeTrackers {
                summary.names += 1
                return fuzzName(string)
            }
            return string
        }
        if lower.hasSuffix("name") {
            if options.includeNames { return string }
            summary.names += 1
            // Path fuzzing also preserves extensions, which matters for torrent
            // and file names (UI shape) as well as paths.
            return fuzzPath(string)
        }
        if lower.hasSuffix("path") || lower.hasSuffix("dir") {
            summary.paths += 1
            return fuzzPath(string)
        }
        if lower == "hashstring" {
            summary.hashes += 1
            return options.includeHashes ? string : fuzzHash(string)
        }
        if lower == "errorstring" || lower == "lastannounceresult" {
            summary.freeTextFields += 1
            return scrubFreeText(string)
        }
        return string
    }

    // MARK: - Trackers

    /// Rewrites an announce/scrape URL to `scheme://<fake-host>/announce`,
    /// dropping the query string (the classic passkey carrier) and any
    /// passkey-shaped path. When tracker anonymization is off, the real host is
    /// kept but the query / passkey path is still stripped. Falls back to
    /// `fakeHost(for:)` for bare hostnames.
    private func rewriteTrackerURL(_ string: String) -> (String, Int) {
        guard let url = URL(string: string),
            let scheme = url.scheme, scheme.lowercased().hasPrefix("http"),
            let host = url.host
        else {
            return (options.anonymizeTrackers ? fakeHost(for: string) : string, 0)
        }
        var passkeys = 0
        let hasQuery = url.query.map { !$0.isEmpty } ?? false
        let path = url.path
        let unusualPath = !path.isEmpty && path != "/" && path != "/announce"
        if hasQuery || unusualPath { passkeys = 1 }

        let fake = options.anonymizeTrackers ? fakeHost(for: host) : host
        let port: String
        if let urlPort = url.port, urlPort != 80, urlPort != 443 {
            port = ":\(urlPort)"
        } else {
            port = ""
        }
        return ("\(scheme)://\(fake)\(port)/announce", passkeys)
    }

    /// Maps an original tracker host (bare hostname, `host:port`, or IP) to a
    /// stable fake: `tracker-N.invalid` for hostnames, a doc-range IP for IPs.
    /// Already-fake `.invalid` hosts pass through untouched, so the free-text
    /// scrub can't re-fake its own output.
    private func fakeHost(for raw: String) -> String {
        if raw.lowercased().hasSuffix(".invalid") { return raw }
        var host = raw
        var port = ""
        if let url = URL(string: raw), let hostname = url.host {
            host = hostname
            if let urlPort = url.port, urlPort != 80, urlPort != 443 { port = ":\(urlPort)" }
        } else if raw.count(where: { $0 == ":" }) == 1, let colon = raw.lastIndex(of: ":") {
            let suffix = raw[raw.index(after: colon)...]
            if !suffix.isEmpty, suffix.allSatisfy(\.isNumber) {
                host = String(raw[..<colon])
                port = ":\(suffix)"
            }
        }
        if isIPAddress(host) {
            return fakeIP(host) + port
        }
        if let existing = state.hostMap[host] {
            return existing + port
        }
        state.nextHostIndex += 1
        let fake = "tracker-\(state.nextHostIndex).invalid"
        state.hostMap[host] = fake
        return fake + port
    }

    // MARK: - Peers

    /// Rewrites a peer address (`1.2.3.4:port`, `[2001:db8::1]:port`, or a bare
    /// IP) to a deterministic doc-range fake, preserving the port.
    private func rewritePeerAddress(_ string: String) -> String {
        var ip = string
        var port: String?
        if string.hasPrefix("[") {
            if let close = string.firstIndex(of: "]") {
                ip = String(string[string.index(after: string.startIndex)..<close])
                let rest = string[string.index(after: close)...]
                if rest.hasPrefix(":"), rest.count > 1 { port = String(rest.dropFirst()) }
            }
        } else if let lastColon = string.lastIndex(of: ":"),
            string.count(where: { $0 == ":" }) == 1
        {
            let suffix = string[string.index(after: lastColon)...]
            if !suffix.isEmpty, suffix.allSatisfy(\.isNumber) {
                ip = String(string[..<lastColon])
                port = String(suffix)
            }
        }
        let fake = fakeIP(ip)
        return port.map { "\(fake):\($0)" } ?? fake
    }

    /// IPv4 → `203.0.113.x` (RFC 5737), IPv6 → `2001:db8:hhhh:hhhh` (RFC 3849).
    /// Deterministic per input address.
    private func fakeIP(_ ip: String) -> String {
        let seed = fnv1a(ip)
        if ip.contains(":") {
            let first = (seed >> 16) & 0xffff
            let second = seed & 0xffff
            return String(format: "2001:db8:%04x:%04x", first, second)
        }
        let octet = Int(seed % 254) + 1
        return "203.0.113.\(octet)"
    }

    private func isIPAddress(_ string: String) -> Bool {
        if string.contains(":") { return true }
        let octets = string.split(separator: ".")
        return octets.count == 4 && octets.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    // MARK: - Names / paths / hashes

    private func fuzzName(_ string: String, preserveDigitClass: Bool = true) -> String {
        var rng = SplitMix64(seed: fnv1a(string))
        return String(
            string.map { char in
                if char.isLetter {
                    let base: UInt8 = char.isUppercase ? 65 : 97
                    return Character(UnicodeScalar(base + UInt8(rng.next() % 26)))
                }
                if char.isNumber {
                    if preserveDigitClass {
                        return Character(UnicodeScalar(UInt8(48 + rng.next() % 10)))
                    }
                    let base: UInt8 = rng.next() % 2 == 0 ? 65 : 97
                    return Character(UnicodeScalar(base + UInt8(rng.next() % 26)))
                }
                return char
            }
        )
    }

    /// Fuzzes each path component while keeping the last component's extension
    /// and the separator structure — truncation/wrapping behavior in the UI
    /// stays reproducible, but no real path survives.
    private func fuzzPath(_ string: String, preserveDigitClass: Bool = true) -> String {
        string.split(separator: "/", omittingEmptySubsequences: false)
            .map { fuzzComponent(String($0), preserveDigitClass: preserveDigitClass) }
            .joined(separator: "/")
    }

    private func fuzzComponent(_ component: String, preserveDigitClass: Bool = true) -> String {
        if let dot = component.lastIndex(of: "."), dot != component.startIndex {
            let ext = component[component.index(after: dot)...]
            if !ext.isEmpty, ext.count <= 8, ext.allSatisfy({ $0.isLetter || $0.isNumber }) {
                return fuzzName(String(component[..<dot]), preserveDigitClass: preserveDigitClass)
                    + "." + ext
            }
        }
        return fuzzName(component, preserveDigitClass: preserveDigitClass)
    }

    private func fuzzHash(_ string: String) -> String {
        let hex = Array("0123456789abcdef")
        var rng = SplitMix64(seed: fnv1a(string))
        return String((0..<40).map { _ in hex[Int(rng.next() % 16)] })
    }

    // MARK: - Free text

    /// Scrubs URLs, bare FQDNs, IPs, emails, and path tokens out of
    /// human-readable messages (`errorString`, `lastAnnounceResult`); the
    /// surrounding message text is preserved for reproducibility.
    ///
    /// Order matters — each step must not re-process earlier output:
    /// IPs → emails → URLs (scheme-less, so no `://` survives for the leak
    /// check) → bare FQDNs → paths last. URLs must be consumed before the FQDN
    /// pass, otherwise URL path segments like `announce.php` get host-faked.
    private func scrubFreeText(_ string: String) -> String {
        var out = string
        out = replace(out, pattern: #"\b\d{1,3}(\.\d{1,3}){3}(:\d{1,5})?\b"#) { match in
            fakeIP(String(match.split(separator: ":").first ?? ""))
        }
        out = replace(out, pattern: #"\b(?:[0-9a-fA-F]{1,4}:){2,}[0-9a-fA-F]{0,4}\b"#) { fakeIP($0) }
        out = replace(out, pattern: #"[\w.+-]+@[\w.-]+\.[a-zA-Z]{2,}"#) { _ in
            "user@redacted.invalid"
        }
        out = replace(out, pattern: #"https?://[^\s<>"']+"#) { match in
            let url = URL(string: match)
            if let url, let host = url.host {
                return "\(fakeHost(for: host))/announce"
            }
            return "redacted.invalid"
        }
        out = replace(out, pattern: #"\b[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+\b"#) {
            fakeHost(for: $0)
        }
        // Digits become letters here (not the digit-preserving fuzz used for
        // names) so fuzzed paths can't form IP-shaped tokens that would trip
        // the leak check. Runs last: the fake URL's "/announce" may get
        // fuzzed, which is cosmetic.
        out = replace(out, pattern: #"(?:/[\w. -]+)+"#) { fuzzPath($0, preserveDigitClass: false) }
        return out
    }

    // MARK: - Helpers

    private func isTimestampKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        return lower.hasSuffix("date") || lower.hasSuffix("time")
    }

    private func encodeToTree(_ value: some Encodable) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func replace(_ string: String, pattern: String, _ replacer: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return string }
        let ns = string as NSString
        var out = ""
        var last = 0
        for match in regex.matches(in: string, range: NSRange(location: 0, length: ns.length)) {
            let range = match.range
            out += ns.substring(with: NSRange(location: last, length: range.location - last))
            out += replacer(ns.substring(with: range))
            last = range.location + range.length
        }
        out += ns.substring(with: NSRange(location: last, length: ns.length - last))
        return out
    }
}

// MARK: - Deterministic hashing / PRNG

/// FNV-1a 64-bit — stable across process runs (unlike `Hasher`, which is
/// randomly seeded per launch).
func fnv1a(_ string: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in string.utf8 {
        hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
    }
    return hash
}

/// splitmix64 PRNG, deterministic for a given seed.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
