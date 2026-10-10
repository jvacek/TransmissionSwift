import CZlib
import Foundation
import os

private let logger = Logger(subsystem: "net.jvacek.TransmissionSwift", category: "GeoIPService")

/// How often the cached database is re-checked. DB-IP publishes a new release
/// monthly, so `.monthly` is the useful default; more frequent checks only cost
/// a conditional request unless the file actually changed.
public enum GeoIPRefreshFrequency: String, CaseIterable, Codable, Sendable {
    case onStartup
    case daily
    case weekly
    case monthly
}

/// Tuning for `GeoIPService`.
public struct GeoIPServiceConfiguration: Sendable {
    public static let defaultDownloadTimeout: TimeInterval = 60
    /// Don't retry a failed or pending check more than once an hour.
    public static let defaultMinimumRetryInterval: TimeInterval = 60 * 60

    public var downloadTimeout: TimeInterval = Self.defaultDownloadTimeout
    public var minimumRetryInterval: TimeInterval = Self.defaultMinimumRetryInterval
    public var refreshFrequency: GeoIPRefreshFrequency = .monthly

    public init() {}

    public static let `default` = GeoIPServiceConfiguration()
}

/// Downloads (periodically), caches, decompresses and parses DB-IP's free
/// "IP to Country Lite" CSV, then answers IPv4 → ISO-3166 country lookups.
/// Foundation + zlib only, so it stays platform-agnostic.
///
/// Re-checks use a conditional GET, so a check that finds no new release reads
/// no body. Data by DB-IP.com (CC BY 4.0).
public actor GeoIPService {
    private struct CacheMeta: Codable {
        /// The `YYYY-MM` release the cached file came from — which may be the
        /// previous month, if the current month wasn't published yet.
        var downloadedRelease: String?
        var lastSuccess: Date?
        var lastAttempt: Date?
        var etag: String?
        var lastModified: String?
    }

    private enum DownloadResult {
        case data(Data, etag: String?, lastModified: String?)
        case notModified
    }

    private let cacheDirectory: URL
    private let session: URLSession
    private let configuration: GeoIPServiceConfiguration
    private var frequency: GeoIPRefreshFrequency
    private var index: CountryIndex?
    private var loadTask: Task<CountryIndex?, Never>?

    public init(
        cacheDirectory: URL,
        session: URLSession? = nil,
        configuration: GeoIPServiceConfiguration = .default
    ) {
        self.cacheDirectory = cacheDirectory
        self.session = session ?? URLSession(configuration: .ephemeral)
        self.configuration = configuration
        self.frequency = configuration.refreshFrequency
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    public func setRefreshFrequency(_ newValue: GeoIPRefreshFrequency) {
        frequency = newValue
    }

    /// Country code for an IPv4 address, or `nil` when the address is IPv6,
    /// private/unknown, or the database isn't available.
    public func countryCode(forIPv4Address ipAddress: String) async -> String? {
        guard let ip = CountryIndex.ipv4(ipAddress) else { return nil }
        guard let index = await ensureIndex() else { return nil }
        return index.countryCode(forIPv4: ip)
    }

    private func ensureIndex() async -> CountryIndex? {
        if let index { return index }
        if let loadTask { return await loadTask.value }
        let task = Task { await load() }
        loadTask = task
        let result = await task.value
        loadTask = nil
        index = result
        return result
    }

    private func load() async -> CountryIndex? {
        await refreshCacheIfNeeded()
        let url = compressedDatabaseURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.warning("GeoIP database unavailable; peer flags disabled")
            return nil
        }
        guard let csv = Self.readGzip(at: url) else {
            logger.error("Failed to decompress GeoIP database at \(url.path, privacy: .public)")
            return nil
        }
        logger.info("Parsing GeoIP database (\(csv.utf8.count) bytes)")
        return CountryIndex(csv: csv)
    }

    private func refreshCacheIfNeeded() async {
        let now = Date()
        let meta = readMeta()
        let currentMonth = Self.month(offset: 0)
        let hasFile = FileManager.default.fileExists(atPath: compressedDatabaseURL.path)
        guard
            Self.needsDownload(
                hasFile: hasFile,
                downloadedRelease: meta?.downloadedRelease,
                lastSuccess: meta?.lastSuccess,
                lastAttempt: meta?.lastAttempt,
                currentMonth: currentMonth,
                frequency: frequency,
                now: now,
                minimumRetryInterval: configuration.minimumRetryInterval
            )
        else { return }

        // The current month's file 404s until DB-IP publishes it early in the
        // month, so fall back to the previous one.
        var hit: (month: String, result: DownloadResult)?
        for offset in 0...1 {
            let month = Self.month(offset: -offset)
            if let result = await download(month: month, priorRelease: meta?.downloadedRelease, meta: meta) {
                hit = (month, result)
                break
            }
        }

        guard let hit else {
            writeMeta(
                CacheMeta(
                    downloadedRelease: meta?.downloadedRelease,
                    lastSuccess: meta?.lastSuccess,
                    lastAttempt: now,
                    etag: meta?.etag,
                    lastModified: meta?.lastModified
                ))
            logger.warning("GeoIP database download failed (current and previous month)")
            return
        }

        switch hit.result {
        case .data(let data, let etag, let lastModified):
            try? data.write(to: compressedDatabaseURL, options: .atomic)
            writeMeta(
                CacheMeta(
                    downloadedRelease: hit.month,
                    lastSuccess: now,
                    lastAttempt: now,
                    etag: etag,
                    lastModified: lastModified
                ))
            logger.info("GeoIP database updated for \(hit.month, privacy: .public)")
        case .notModified:
            writeMeta(
                CacheMeta(
                    downloadedRelease: hit.month,
                    lastSuccess: now,
                    lastAttempt: now,
                    etag: meta?.etag,
                    lastModified: meta?.lastModified
                ))
            logger.info("GeoIP database unchanged for \(hit.month, privacy: .public)")
        }
    }

    private func download(month: String, priorRelease: String?, meta: CacheMeta?) async -> DownloadResult? {
        guard let url = URL(string: "https://download.db-ip.com/free/dbip-country-lite-\(month).csv.gz") else {
            return nil
        }
        var request = URLRequest(url: url, timeoutInterval: configuration.downloadTimeout)
        request.setValue("TransmissionSwift", forHTTPHeaderField: "User-Agent")
        // Only revalidate against the release we already have; a different URL
        // would just be answered with a full 200 anyway.
        if month == priorRelease {
            if let etag = meta?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            if let modified = meta?.lastModified {
                request.setValue(modified, forHTTPHeaderField: "If-Modified-Since")
            }
        }
        guard let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse
        else { return nil }
        if http.statusCode == 304 { return .notModified }
        guard http.statusCode == 200, !data.isEmpty else { return nil }
        return .data(
            data,
            etag: http.value(forHTTPHeaderField: "ETag"),
            lastModified: http.value(forHTTPHeaderField: "Last-Modified"))
    }

    /// Whether to hit the network now. A missing cache, or a cached file from an
    /// older release, is always due once the one-hour retry floor has passed;
    /// otherwise the user's frequency decides. Internal for testing.
    static func needsDownload(
        hasFile: Bool,
        downloadedRelease: String?,
        lastSuccess: Date?,
        lastAttempt: Date?,
        currentMonth: String,
        frequency: GeoIPRefreshFrequency,
        now: Date,
        minimumRetryInterval: TimeInterval = GeoIPServiceConfiguration.defaultMinimumRetryInterval,
        calendar: Calendar = .current
    ) -> Bool {
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < minimumRetryInterval {
            return false
        }
        guard hasFile, let downloadedRelease else { return true }
        if downloadedRelease != currentMonth { return true }
        guard let lastSuccess else { return true }
        switch frequency {
        case .onStartup: return true
        case .daily: return !calendar.isDate(lastSuccess, equalTo: now, toGranularity: .day)
        case .weekly: return !calendar.isDate(lastSuccess, equalTo: now, toGranularity: .weekOfYear)
        case .monthly: return !calendar.isDate(lastSuccess, equalTo: now, toGranularity: .month)
        }
    }

    private var compressedDatabaseURL: URL {
        cacheDirectory.appendingPathComponent("dbip-country-lite.csv.gz")
    }

    private var metaURL: URL {
        cacheDirectory.appendingPathComponent("dbip-country-lite.meta.json")
    }

    private func readMeta() -> CacheMeta? {
        guard let data = try? Data(contentsOf: metaURL) else { return nil }
        return try? JSONDecoder().decode(CacheMeta.self, from: data)
    }

    private func writeMeta(_ meta: CacheMeta) {
        try? JSONEncoder().encode(meta).write(to: metaURL, options: .atomic)
    }

    private static func month(offset: Int) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(byAdding: .month, value: offset, to: Date()) ?? Date()
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    /// Streams the gzip file through zlib into one string. ~30 MB decompressed
    /// for the full database, parsed off the main actor.
    private static func readGzip(at url: URL) -> String? {
        guard let file = gzopen(url.path, "rb") else { return nil }
        defer { _ = gzclose(file) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1 << 16)
        while true {
            let read = gzread(file, &buffer, UInt32(buffer.count))
            guard read > 0 else { break }
            data.append(contentsOf: buffer[0..<Int(read)])
        }
        return String(decoding: data, as: UTF8.self)
    }
}
