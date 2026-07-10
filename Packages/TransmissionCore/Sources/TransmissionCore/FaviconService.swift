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

    public var requestTimeout: TimeInterval = Self.defaultRequestTimeout
    public var maxRedirects: Int = Self.defaultMaxRedirects
    public var revalidationInterval: TimeInterval = Self.defaultRevalidationInterval

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
    /// usable icon could be resolved. `forceRevalidate` issues a conditional GET
    /// even when the cache is still fresh (used for the startup update check).
    public func icon(for host: String, forceRevalidate: Bool = false) async -> Data? {
        guard !host.isEmpty, let base = URL(string: "https://" + host) else { return nil }
        logger.info("Fetching favicon for host: \(host, privacy: .public) (forceRevalidate: \(forceRevalidate))")
        let cached = readCached(host: host)
        if let cached, !forceRevalidate, Date().timeIntervalSince(cached.meta.fetchedAt) < revalidationInterval {
            logger.info(
                "Returning cached favicon for \(host, privacy: .public) (age: \(Date().timeIntervalSince(cached.meta.fetchedAt), privacy: .public)s)"
            )
            return cached.data
        }
        let candidates = await candidateURLs(host: host, base: base)
        logger.debug(
            "Candidate URLs for \(host, privacy: .public): \(candidates.map(\.absoluteString), privacy: .public)")
        for url in candidates.prefix(maxAttempts) {
            logger.debug("Trying \(url.absoluteString, privacy: .public) for \(host, privacy: .public)")
            if let result = await fetch(url: url, meta: cached?.meta) {
                writeCached(
                    host: host, data: result.data, sourceURL: result.url, etag: result.etag,
                    lastModified: result.lastModified)
                logger.info(
                    "Successfully fetched favicon for \(host, privacy: .public) from \(result.url.absoluteString, privacy: .public) (\(result.data.count) bytes)"
                )
                return result.data
            } else {
                logger.debug(
                    "Failed to fetch favicon from \(url.absoluteString, privacy: .public) for \(host, privacy: .public)"
                )
            }
        }
        logger.warning("All favicon candidates failed for \(host, privacy: .public), returning cached if available")
        return cached?.data
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

    private func fetch(url: URL, meta: FaviconCacheMeta?) async
        -> (data: Data, url: URL, etag: String?, lastModified: String?)?
    {
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.setValue("TransmissionSwift", forHTTPHeaderField: "User-Agent")
        if let etag = meta?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lm = meta?.lastModified { request.setValue(lm, forHTTPHeaderField: "If-Modified-Since") }
        guard let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse
        else { return nil }
        if http.statusCode == 304 { return nil }
        guard (200...299).contains(http.statusCode) else { return nil }
        guard let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(), type.hasPrefix("image/") else {
            return nil
        }
        guard !data.isEmpty, data.count <= Self.maxIconBytes else { return nil }
        return (data, url, http.value(forHTTPHeaderField: "ETag"), http.value(forHTTPHeaderField: "Last-Modified"))
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

    private func readCached(host: String) -> (data: Data, meta: FaviconCacheMeta)? {
        let dURL = dataURL(host: host)
        let mURL = metaURL(host: host)
        guard let data = try? Data(contentsOf: dURL),
            let metaData = try? Data(contentsOf: mURL),
            let meta = try? JSONDecoder().decode(FaviconCacheMeta.self, from: metaData)
        else { return nil }
        return (data, meta)
    }

    private func writeCached(host: String, data: Data, sourceURL: URL, etag: String?, lastModified: String?) {
        let meta = FaviconCacheMeta(
            sourceURL: sourceURL.absoluteString,
            etag: etag,
            lastModified: lastModified,
            fetchedAt: Date()
        )
        try? data.write(to: dataURL(host: host), options: .atomic)
        try? JSONEncoder().encode(meta).write(to: metaURL(host: host), options: .atomic)
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
