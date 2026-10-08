import Foundation

/// Tripwire that refuses to ship a snapshot if anything identifying survived
/// redaction. Runs after redaction, before writing the file.
///
/// Key-aware: fields the redactor fully transforms (paths, hashes, and — when
/// the relevant opt-in is off — names and tracker hosts) are skipped, since
/// fuzzed contents can legitimately look like arbitrary text (e.g. a fuzzed
/// file name "qwer.ty"). Kept names get an IP check only (no FQDN check —
/// real names contain dots). Kept tracker hosts are intentional, so only the
/// passkey query tripwire applies to them. Everything else is scanned for
/// IPs / hostnames / unscrubbed URLs.
public enum SnapshotLeakChecker {
    /// Throws `SnapshotError.leakDetected` listing every offending value.
    ///
    /// - Parameters:
    ///   - namesKept: `true` when the capture kept real names (`includeNames`),
    ///     so name fields are checked for embedded IPs.
    ///   - anonymizeTrackers: `true` when tracker hosts/sitenames were fuzzed,
    ///     so tracker fields must only contain `.invalid` hosts / doc-range IPs.
    public static func check(
        _ tree: [String: Any],
        namesKept: Bool = false,
        anonymizeTrackers: Bool = true
    ) throws {
        var leaks: [String] = []
        walk(
            tree, key: "root", path: "$", namesKept: namesKept,
            anonymizeTrackers: anonymizeTrackers, leaks: &leaks)
        if !leaks.isEmpty {
            throw SnapshotError.leakDetected(details: leaks)
        }
    }

    private static func walk(
        _ value: Any, key: String, path: String, namesKept: Bool, anonymizeTrackers: Bool,
        leaks: inout [String]
    ) {
        if let dict = value as? [String: Any] {
            // Sorted for deterministic traversal (NSDictionary order is not
            // stable across runs) — keeps leak reports and behavior stable.
            for childKey in dict.keys.sorted() {
                walk(
                    dict[childKey]!, key: childKey, path: "\(path).\(childKey)",
                    namesKept: namesKept, anonymizeTrackers: anonymizeTrackers, leaks: &leaks)
            }
            return
        }
        if let array = value as? [Any] {
            // Elements inherit their parent's key — matches how the redactor
            // classifies values inside arrays (labels, peers, trackers).
            for (index, child) in array.enumerated() {
                walk(
                    child, key: key, path: "\(path)[\(index)]", namesKept: namesKept,
                    anonymizeTrackers: anonymizeTrackers, leaks: &leaks)
            }
            return
        }
        guard let string = value as? String else { return }
        check(
            string, key: key, path: path, namesKept: namesKept,
            anonymizeTrackers: anonymizeTrackers, leaks: &leaks)
    }

    private enum FieldKind {
        case skipped  // fully transformed by the redactor
        case nameKept  // kept real (includeNames) — checked for IPs only
        case hostLike  // tracker URLs / hosts
        case peerAddress
        case freeText  // errorString / lastAnnounceResult
        case generic
    }

    private static func kind(for key: String, namesKept: Bool) -> FieldKind {
        let lower = key.lowercased()
        // Always transformed (or intentional tracker metadata): no checks.
        if lower == "clientname" || lower == "sitename" || lower == "hashstring"
            || lower.hasSuffix("path") || lower.hasSuffix("dir")
        {
            return .skipped
        }
        if lower == "labels" || lower.hasSuffix("name") {
            return namesKept ? .nameKept : .skipped
        }
        if lower.hasSuffix("announce") || lower.hasSuffix("scrape") || lower.hasSuffix("url")
            || lower.hasSuffix("host")
        {
            return .hostLike
        }
        if lower.hasSuffix("address") { return .peerAddress }
        if lower == "errorstring" || lower == "lastannounceresult" { return .freeText }
        return .generic
    }

    private static func check(
        _ string: String, key: String, path: String, namesKept: Bool, anonymizeTrackers: Bool,
        leaks: inout [String]
    ) {
        switch kind(for: key, namesKept: namesKept) {
        case .skipped, .generic:
            return
        case .nameKept:
            // Real names can contain anything except embedded IPs.
            checkIPs(string, path: path, leaks: &leaks)
        case .hostLike:
            if string.contains("?") {
                leaks.append("\(path): query string on tracker URL (possible passkey)")
            }
            guard anonymizeTrackers else { return }  // kept hosts are intentional
            if string.lowercased().contains(".onion") {
                leaks.append("\(path): .onion host")
            }
            checkIPs(string, path: path, leaks: &leaks)
            checkFQDNs(string, path: path, leaks: &leaks)
        case .peerAddress:
            if string.contains("?") {
                leaks.append("\(path): unexpected query string")
            }
            checkIPs(string, path: path, leaks: &leaks)
        case .freeText:
            if string.contains("://") {
                leaks.append("\(path): unscrubbed URL")
            }
            if string.lowercased().contains(".onion") {
                leaks.append("\(path): .onion host")
            }
            if string.lowercased().contains("?key=") {
                leaks.append("\(path): passkey query remnant")
            }
            checkIPs(string, path: path, leaks: &leaks)
        }
    }

    // MARK: - IP checks

    private static func checkIPs(_ string: String, path: String, leaks: inout [String]) {
        for token in matches(in: string, pattern: #"\b\d{1,3}(\.\d{1,3}){3}\b"#) {
            let octets = token.split(separator: ".").compactMap { Int($0) }
            if octets.count == 4, !isAllowedIPv4(octets) {
                leaks.append("\(path): non-doc IPv4 '\(token)'")
            }
        }
        for token in matches(in: string, pattern: #"[0-9a-fA-F:]+"#) {
            guard let trimmed = stripPortIfPresent(token), isLikelyIPv6(trimmed) else { continue }
            if !trimmed.lowercased().hasPrefix("2001:db8") {
                leaks.append("\(path): non-doc IPv6 '\(trimmed)'")
            }
        }
    }

    /// IPv4 is allowed only in the RFC 5737 documentation ranges plus loopback
    /// — the only places the redactor emits addresses.
    private static func isAllowedIPv4(_ octets: [Int]) -> Bool {
        if octets[0] == 127 { return true }
        return (octets[0] == 192 && octets[1] == 0 && octets[2] == 2)
            || (octets[0] == 198 && octets[1] == 51 && octets[2] == 100)
            || (octets[0] == 203 && octets[1] == 0 && octets[2] == 113)
    }

    /// Drops a trailing `:port` (e.g. "2001:db8:abcd:ef01:51413") so the
    /// remaining token can be validated as an IPv6 address.
    private static func stripPortIfPresent(_ token: String) -> String? {
        guard let colon = token.lastIndex(of: ":") else { return nil }
        let suffix = token[token.index(after: colon)...]
        if suffix.allSatisfy(\.isNumber), !suffix.isEmpty, token.count(where: { $0 == ":" }) >= 2 {
            return String(token[..<colon])
        }
        return token
    }

    /// Loose IPv6 plausibility: at least two colons, every segment (dropping a
    /// `::` empty segment) is 1-4 hex digits.
    private static func isLikelyIPv6(_ token: String) -> Bool {
        let lower = token.lowercased()
        guard lower.count(where: { $0 == ":" }) >= 2 else { return false }
        return lower.split(separator: ":").allSatisfy {
            !$0.isEmpty && $0.count <= 4 && $0.allSatisfy(\.isHexDigit)
        }
    }

    // MARK: - Hostname checks

    /// Hostnames are allowed only as `*.invalid` (the redactor's fake TLD) or
    /// `localhost`. Hostname-looking tokens elsewhere mean something real
    /// survived.
    private static func checkFQDNs(_ string: String, path: String, leaks: inout [String]) {
        let pattern = #"\b[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+\b"#
        for token in matches(in: string, pattern: pattern) {
            let lower = token.lowercased()
            if lower != "localhost" && !lower.hasSuffix(".invalid") {
                leaks.append("\(path): non-fake hostname '\(token)'")
            }
        }
    }

    // MARK: - Helpers

    private static func matches(in string: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = string as NSString
        return regex.matches(in: string, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }
}
