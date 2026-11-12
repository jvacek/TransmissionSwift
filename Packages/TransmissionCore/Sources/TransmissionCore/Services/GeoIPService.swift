// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

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
    /// A new month's file 404s until DB-IP publishes it, and the cached older
    /// release would otherwise make every hourly check look due. Retry that
    /// case at most once a day.
    static let missingReleaseRetryInterval: TimeInterval = 24 * 60 * 60

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
        var downloadedRelease: String? = nil
        var lastSuccess: Date? = nil
        var lastAttempt: Date? = nil
        var etag: String? = nil
        var lastModified: String? = nil
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
    private var hasCheckedThisLaunch = false
    private var lastCheck: Date?

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
        if let index {
            guard isRefreshDue else { return index }
            // Reload only when the refresh replaced the file; a 304 keeps the
            // parsed index. A replacement that fails to parse also keeps it,
            // so one bad download can't disable flags for the whole process.
            if await refreshCacheIfNeeded(), let loaded = await load() {
                self.index = loaded
            }
            if let loaded = self.index { return loaded }
        }
        if let loadTask { return await loadTask.value }
        let task = Task { await load() }
        loadTask = task
        let result = await task.value
        loadTask = nil
        index = result
        return result
    }

    /// `.onStartup` is a once-per-process check; every other cadence re-checks
    /// after the retry floor so a long-running app still picks up new releases.
    private var isRefreshDue: Bool {
        if frequency == .onStartup { return !hasCheckedThisLaunch }
        guard let lastCheck else { return true }
        return Date().timeIntervalSince(lastCheck) >= configuration.minimumRetryInterval
    }

    private func load() async -> CountryIndex? {
        await refreshCacheIfNeeded()
        let url = compressedDatabaseURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.warning("GeoIP database unavailable; peer flags disabled")
            return nil
        }
        guard let index = CountryIndex(gzipAt: url) else {
            logger.error(
                "GeoIP database at \(url.path, privacy: .public) is unreadable; discarding it")
            discardCachedDatabase()
            return nil
        }
        logger.info(
            "Parsed GeoIP database from \(url.lastPathComponent, privacy: .public) (\(index.rowCount) rows)"
        )
        return index
    }

    /// Removes a database that parsed to nothing, keeping the retry floor so a
    /// server that keeps answering with an error page isn't hammered. The next
    /// due check downloads unconditionally because the cached meta is gone.
    private func discardCachedDatabase() {
        try? FileManager.default.removeItem(at: compressedDatabaseURL)
        writeMeta(CacheMeta(lastAttempt: Date()))
    }

    /// Returns true when a new database file was written, so the parsed index
    /// must be rebuilt.
    @discardableResult
    private func refreshCacheIfNeeded() async -> Bool {
        let now = Date()
        // Mark the check before the first await so a concurrent lookup returns
        // the current index instead of starting a second download.
        hasCheckedThisLaunch = true
        lastCheck = now
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
        else { return false }

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
            return false
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
            return true
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
            return false
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
    /// older release, is due once the retry floor has passed (one hour
    /// normally, one day while waiting for the current month's release);
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
        // A cached file from an older release means the current month's file
        // isn't published yet. Keep re-checking, but no more than once a day
        // instead of on every hourly service check.
        let retryFloor =
            hasFile && downloadedRelease != nil && downloadedRelease != currentMonth
            ? max(minimumRetryInterval, GeoIPServiceConfiguration.missingReleaseRetryInterval)
            : minimumRetryInterval
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < retryFloor {
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
}
