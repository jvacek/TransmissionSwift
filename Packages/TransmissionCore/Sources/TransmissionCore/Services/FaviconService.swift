import Foundation
import os

private let logger = Logger(subsystem: "net.jvacek.TransmissionSwift", category: "FaviconService")

private struct FaviconCacheMeta: Codable {
    var sourceURL: String
    var etag: String?
    var lastModified: String?
    var fetchedAt: Date
}

/// Configuration for the favicon service.
public struct FaviconServiceConfiguration: Sendable {
    public static let defaultRequestTimeout: TimeInterval = 8
    public static let defaultMaxRedirects = 5
    public static let defaultRevalidationInterval: TimeInterval = 7 * 86_400
    /// How long a host that produced no icon is remembered as a miss. Shorter
    /// than `revalidationInterval` because a domain can start serving one at any time.
    public static let defaultNegativeCacheInterval: TimeInterval = 24 * 3600

    public var requestTimeout: TimeInterval = Self.defaultRequestTimeout
    public var maxRedirects: Int = Self.defaultMaxRedirects
    public var revalidationInterval: TimeInterval = Self.defaultRevalidationInterval
    public var negativeCacheInterval: TimeInterval = Self.defaultNegativeCacheInterval

    public init() {}

    public static let `default` = FaviconServiceConfiguration()
}

/// Fetches, caches, and revalidates tracker favicons entirely on Foundation
/// primitives so the core stays platform-agnostic. Returns raw image `Data`;
/// turning that into an `NSImage`/`Image` is the app target's job.
public actor FaviconService {
    public static let maxIconBytes = 3_000_000

    private let cacheDirectory: URL
    private let session: URLSession
    private let revalidationInterval: TimeInterval
    private let negativeCacheInterval: TimeInterval
    private let requestTimeout: TimeInterval
    private let maxRedirects: Int
    private let maxAttempts = 8

    public init(
        cacheDirectory: URL,
        session: URLSession? = nil,
        configuration: FaviconServiceConfiguration = .default
    ) {
        self.cacheDirectory = cacheDirectory
        self.revalidationInterval = configuration.revalidationInterval
        self.negativeCacheInterval = configuration.negativeCacheInterval
        self.requestTimeout = configuration.requestTimeout
        self.maxRedirects = configuration.maxRedirects

        // Create a session with a custom delegate to limit redirects
        if let session = session {
            self.session = session
        } else {
            let delegate = FaviconSessionDelegate(maxRedirects: maxRedirects)
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = requestTimeout
            config.timeoutIntervalForResource = requestTimeout * 2
            self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        }
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Returns cached-or-fetched favicon data for `host`, or `nil` when no
    /// usable icon could be resolved.
    ///
    /// A positive cache entry is revalidated with a single conditional GET to
    /// the URL that produced it, so a stale icon never re-runs discovery. A miss
    /// is negative-cached for `negativeCacheInterval`, so a host known to serve
    /// no icon costs no network. `forceRevalidate` bypasses the freshness
    /// short-circuit and revalidates the recorded source early.
    public func icon(for host: String, forceRevalidate: Bool = false) async -> Data? {
        guard !host.isEmpty, let base = URL(string: "https://" + host) else { return nil }
        logger.info("Fetching favicon for host: \(host, privacy: .public) (forceRevalidate: \(forceRevalidate))")

        let cachedData = readData(host: host)
        let meta = readMeta(host: host)
        let age = meta.map { Date().timeIntervalSince($0.fetchedAt) } ?? 0

        if let cachedData {
            if meta != nil, !forceRevalidate, age < revalidationInterval {
                logger.info(
                    "Returning cached favicon for \(host, privacy: .public) (age: \(age, privacy: .public)s)")
                return cachedData
            }
            // Stale or forced: revalidate the source we recorded instead of
            // re-running discovery. Handles the common path in one request.
            if let meta, !meta.sourceURL.isEmpty, let sourceURL = URL(string: meta.sourceURL) {
                switch await fetch(url: sourceURL, meta: meta) {
                case .notModified:
                    touchMeta(host: host, meta: meta)
                    return cachedData
                case .image(let data, let url, let etag, let lastModified):
                    writeCached(host: host, data: data, sourceURL: url, etag: etag, lastModified: lastModified)
                    return data
                case .transportFailure:
                    return cachedData
                case .httpFailure:
                    break  // source moved; fall through to discovery
                }
            }
        } else if meta != nil, !forceRevalidate, age < negativeCacheInterval {
            logger.info("Negative favicon cache hit for \(host, privacy: .public) (age: \(age, privacy: .public)s)")
            return nil
        }

        let candidates = await candidateURLs(host: host, base: base)
        logger.debug(
            "Candidate URLs for \(host, privacy: .public): \(candidates.map(\.absoluteString), privacy: .public)")
        for url in candidates.prefix(maxAttempts) {
            logger.debug("Trying \(url.absoluteString, privacy: .public) for \(host, privacy: .public)")
            switch await fetch(url: url, meta: nil) {
            case .image(let data, let sourceURL, let etag, let lastModified):
                writeCached(host: host, data: data, sourceURL: sourceURL, etag: etag, lastModified: lastModified)
                logger.info(
                    "Successfully fetched favicon for \(host, privacy: .public) from \(sourceURL.absoluteString, privacy: .public) (\(data.count) bytes)"
                )
                return data
            case .notModified:
                // Impossible without validators; treat as a miss for this candidate.
                continue
            case .httpFailure, .transportFailure:
                logger.debug(
                    "Failed to fetch favicon from \(url.absoluteString, privacy: .public) for \(host, privacy: .public)"
                )
            }
        }
        if let cachedData {
            logger.warning("All favicon candidates failed for \(host, privacy: .public), returning stale cache")
            return cachedData
        }
        logger.warning("All favicon candidates failed for \(host, privacy: .public), negative-caching the miss")
        writeNegative(host: host)
        return nil
    }

    private func candidateURLs(host: String, base: URL) async -> [URL] {
        var urls: [URL] = []

        // 1. Try HTML parsing on the base URL (e.g., https://tracker.example.com)
        if let html = await fetchHTML(base: base), !html.isEmpty {
            let links = extractIconLinks(html: html, base: base)
            urls.append(contentsOf: links.map(\.url))
        }

        // 2. Try base domain fallback (e.g., tracker.deepbassnine.com → deepbassnine.com)
        // This handles trackers that serve favicons only from the main domain
        let baseDomain = extractBaseDomain(host)
        if baseDomain != host {
            let baseDomainURL = URL(string: "https://" + baseDomain)!
            if let html = await fetchHTML(base: baseDomainURL), !html.isEmpty {
                let links = extractIconLinks(html: html, base: baseDomainURL)
                urls.append(contentsOf: links.map(\.url))
            }
        }

        // 3. Static paths on the original host
        let staticPaths = [
            "/apple-touch-icon.png",
            "/apple-touch-icon-precomposed.png",
            "/apple-touch-icon-180x180-precomposed.png",
            "/apple-touch-icon-152x152-precomposed.png",
            "/favicon.svg",
            "/favicon.ico",
        ]
        for path in staticPaths {
            if let url = URL(string: path, relativeTo: base) { urls.append(url) }
        }

        // 4. Static paths on base domain (if different)
        if baseDomain != host {
            let baseDomainURL = URL(string: "https://" + baseDomain)!
            for path in staticPaths {
                if let url = URL(string: path, relativeTo: baseDomainURL) { urls.append(url) }
            }
        }

        return urls
    }

    /// Extract the base domain (e.g., "tracker.deepbassnine.com" → "deepbassnine.com")
    /// Handles common ccTLDs (co.uk, com.au, etc.) and known public suffixes.
    private func extractBaseDomain(_ host: String) -> String {
        let parts = host.split(separator: ".")
        guard parts.count >= 2 else { return host }

        // Common public suffixes where the registrable domain is 3 parts
        let commonPublicSuffixes: Set<String> = [
            "ac", "co", "com", "edu", "gov", "net", "org", "mil", "int",
            "arpa", "museum", "aero", "coop", "info", "name", "pro",
            "biz", "mobi", "asia", "cat", "jobs", "tel", "travel",
            "xxx", "post", "xyz", "online", "site", "store", "tech",
            "space", "website", "club", "app", "dev", "page", "blog",
        ]

        let tld = String(parts.last!)
        let secondLevel = String(parts[parts.count - 2])

        // Check if second-level is a common public suffix (e.g., co.uk, com.au)
        if commonPublicSuffixes.contains(secondLevel.lowercased()) && parts.count >= 3 {
            let thirdLevel = String(parts[parts.count - 3])
            let candidate = "\(thirdLevel).\(secondLevel).\(tld)"
            if candidate == host { return host }
            return candidate
        }

        // Standard case: registrable domain is 2 levels
        let candidate = "\(secondLevel).\(tld)"
        if candidate == host { return host }
        return candidate
    }

    private func fetchHTML(base: URL) async -> String? {
        var request = URLRequest(url: base, timeoutInterval: requestTimeout)
        request.setValue("TransmissionSwift", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse,
            (200...299).contains(http.statusCode),
            let type = http.value(forHTTPHeaderField: "Content-Type"), type.contains("html"),
            data.count < 512_000,
            let html = String(data: data, encoding: .utf8)
        else { return nil }
        return html
    }

    private enum FetchOutcome {
        case notModified
        case image(data: Data, url: URL, etag: String?, lastModified: String?)
        /// The server answered, but not with a usable image (404, 410, wrong content type, ...).
        case httpFailure
        /// No usable response at all (offline, timeout, ...).
        case transportFailure
    }

    private func fetch(url: URL, meta: FaviconCacheMeta?) async -> FetchOutcome {
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.setValue("TransmissionSwift", forHTTPHeaderField: "User-Agent")
        if let etag = meta?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lm = meta?.lastModified { request.setValue(lm, forHTTPHeaderField: "If-Modified-Since") }
        guard let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse
        else { return .transportFailure }
        if http.statusCode == 304 { return .notModified }
        guard (200...299).contains(http.statusCode) else { return .httpFailure }
        guard let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(), type.hasPrefix("image/") else {
            return .httpFailure
        }
        guard !data.isEmpty, data.count <= Self.maxIconBytes else { return .httpFailure }
        return .image(
            data: data, url: url, etag: http.value(forHTTPHeaderField: "ETag"),
            lastModified: http.value(forHTTPHeaderField: "Last-Modified"))
    }

    private func extractIconLinks(html: String, base: URL) -> [(url: URL, priority: Int)] {
        guard let linkRegex = try? NSRegularExpression(pattern: #"<link\b[^>]*>"#, options: .caseInsensitive) else {
            return []
        }
        let fullRange = NSRange(html.startIndex..., in: html)
        var results: [(URL, Int)] = []
        for match in linkRegex.matches(in: html, range: fullRange) {
            guard let range = Range(match.range, in: html) else { continue }
            let tag = String(html[range])
            guard let rel = attribute(tag, name: "rel")?.lowercased(), rel.contains("icon") else { continue }
            guard let href = attribute(tag, name: "href"),
                let url = URL(string: href, relativeTo: base)
            else { continue }
            let type = attribute(tag, name: "type")?.lowercased()
            let isAppleTouch = rel.contains("apple-touch-icon")
            let isSVG = type == "image/svg+xml" || url.pathExtension.lowercased() == "svg"
            let sizes = attribute(tag, name: "sizes") ?? ""
            var priority = 100
            if isAppleTouch {
                priority = sizes.contains("180") ? 0 : 1
            } else if isSVG {
                priority = 2
            } else if sizes.contains("128") || sizes.contains("96") || sizes.contains("64") {
                priority = 3
            } else {
                priority = 4
            }
            results.append((url, priority))
        }
        results.sort { $0.1 < $1.1 }
        return results
    }

    private func attribute(_ tag: String, name: String) -> String? {
        let pattern = #"\b"# + name + #"\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let tagRange = NSRange(tag.startIndex..., in: tag)
        guard let match = regex.firstMatch(in: tag, range: tagRange) else { return nil }
        for group in 2...4 {
            let range = match.range(at: group)
            if range.location != NSNotFound, let valueRange = Range(range, in: tag) {
                return String(tag[valueRange])
            }
        }
        return nil
    }

    private func sanitized(_ host: String) -> String {
        host.replacingOccurrences(of: "/", with: "_")
    }

    private func dataURL(host: String) -> URL {
        cacheDirectory.appendingPathComponent(sanitized(host) + ".bin")
    }

    private func metaURL(host: String) -> URL {
        cacheDirectory.appendingPathComponent(sanitized(host) + ".meta.json")
    }

    private func readData(host: String) -> Data? {
        try? Data(contentsOf: dataURL(host: host))
    }

    private func readMeta(host: String) -> FaviconCacheMeta? {
        guard let metaData = try? Data(contentsOf: metaURL(host: host)) else { return nil }
        return try? JSONDecoder().decode(FaviconCacheMeta.self, from: metaData)
    }

    private func writeMeta(host: String, meta: FaviconCacheMeta) {
        try? JSONEncoder().encode(meta).write(to: metaURL(host: host), options: .atomic)
    }

    private func writeCached(host: String, data: Data, sourceURL: URL, etag: String?, lastModified: String?) {
        let meta = FaviconCacheMeta(
            sourceURL: sourceURL.absoluteString,
            etag: etag,
            lastModified: lastModified,
            fetchedAt: Date()
        )
        try? data.write(to: dataURL(host: host), options: .atomic)
        writeMeta(host: host, meta: meta)
    }

    /// Records a miss (no `.bin`): the presence of `.bin` distinguishes a
    /// positive entry from a negative one.
    private func writeNegative(host: String) {
        writeMeta(
            host: host,
            meta: FaviconCacheMeta(sourceURL: "", etag: nil, lastModified: nil, fetchedAt: Date()))
    }

    /// Marks a positive entry fresh again after a 304 revalidation.
    private func touchMeta(host: String, meta: FaviconCacheMeta) {
        var updated = meta
        updated.fetchedAt = Date()
        writeMeta(host: host, meta: updated)
    }
}

/// URLSessionDelegate that limits the number of redirects to prevent infinite redirect loops.
private final class FaviconSessionDelegate: NSObject, URLSessionTaskDelegate {
    private let maxRedirects: Int
    private let redirectCountsLock = OSAllocatedUnfairLock<[URLSessionTask: Int]>(initialState: [:])

    init(maxRedirects: Int) {
        self.maxRedirects = maxRedirects
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let count = redirectCountsLock.withLock { counts in
            let count = (counts[task] ?? 0) + 1
            counts[task] = count
            return count
        }
        if count > maxRedirects {
            let urlString = task.originalRequest?.url?.absoluteString ?? "unknown"
            logger.warning("Max redirects (\(self.maxRedirects)) exceeded for \(urlString)")
            completionHandler(nil)
            _ = redirectCountsLock.withLock { $0.removeValue(forKey: task) }
        } else {
            completionHandler(request)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        _ = redirectCountsLock.withLock { $0.removeValue(forKey: task) }
    }
}
