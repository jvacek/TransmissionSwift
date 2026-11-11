import Foundation
import Testing
import os

@testable import TransmissionCore

private let auGzip = Data(base64Encoded: "H4sIAAAAAAACAzPUMwBBHUMwbWRqquMYygUA97XRexUAAAA=")!
private let cnGzip = Data(base64Encoded: "H4sIAAAAAAACAzPUMwBBHUMwbWRqquPsxwUAA6pj0RUAAAA=")!

private final class GeoIPStubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let handlers = OSAllocatedUnfairLock<[String: Handler]>(initialState: [:])
    private static let requests = OSAllocatedUnfairLock<[String]>(initialState: [])

    static func register(path: String, handler: @escaping Handler) {
        handlers.withLock { $0[path] = handler }
    }

    static func reset() {
        handlers.withLock { $0.removeAll() }
        requests.withLock { $0.removeAll() }
    }

    static func requestCount() -> Int {
        requests.withLock { $0.count }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GeoIPStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let path = url.path()
        Self.requests.withLock { $0.append(path) }
        guard let handler = Self.handlers.withLock({ $0[path] }) else {
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: [:])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite("GeoIPService", .serialized)
struct GeoIPServiceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func needs(
        hasFile: Bool = true,
        release: String? = "2026-10",
        frequency: GeoIPRefreshFrequency = .daily,
        success: String? = "2026-10-09T12:00:00Z",
        attempt: String? = "2026-09-01T00:00:00Z",
        current: String = "2026-10",
        now: String = "2026-10-09T12:00:00Z"
    ) -> Bool {
        GeoIPService.needsDownload(
            hasFile: hasFile,
            downloadedRelease: release,
            lastSuccess: success.map { date($0) },
            lastAttempt: attempt.map { date($0) },
            currentMonth: current,
            frequency: frequency,
            now: date(now),
            calendar: calendar
        )
    }

    @Test func noCacheIsDue() {
        #expect(needs(hasFile: false, release: nil, success: nil, attempt: nil))
    }

    @Test func retryFloorBlocksRapidAttempts() {
        #expect(!needs(attempt: "2026-10-09T11:30:00Z", now: "2026-10-09T12:00:00Z"))
    }

    @Test func pendingReleaseIsDueRegardlessOfFrequency() {
        // Cached file is September's while the current month is October.
        #expect(needs(release: "2026-09", frequency: .monthly, current: "2026-10"))
    }

    @Test func frequencyGateForCurrentRelease() {
        #expect(!needs(frequency: .daily, success: "2026-10-09T08:00:00Z"))
        #expect(needs(frequency: .daily, success: "2026-10-08T08:00:00Z"))
        #expect(!needs(frequency: .weekly, success: "2026-10-07T08:00:00Z"))
        #expect(needs(frequency: .weekly, success: "2026-09-30T08:00:00Z"))
        #expect(!needs(frequency: .monthly, success: "2026-10-01T08:00:00Z"))
        #expect(needs(frequency: .onStartup, success: "2026-10-09T08:00:00Z"))
    }

    @Test func reloadsANewerReleaseWhileRunning() async throws {
        GeoIPStubURLProtocol.reset()
        let directory = freshCache()
        let month = monthString()
        try writeCache(directory, gzip: auGzip, release: month, success: Date(), attempt: .distantPast)
        let service = GeoIPService(
            cacheDirectory: directory,
            session: GeoIPStubURLProtocol.makeSession(),
            configuration: configuration(.daily))

        #expect(await service.countryCode(forIPv4Address: "1.0.0.1") == "AU")
        #expect(GeoIPStubURLProtocol.requestCount() == 0)

        // The next daily check is now due. Simulate it by aging the meta and
        // serving a changed database, without waiting a day.
        try writeCache(
            directory, gzip: auGzip, release: month,
            success: Date().addingTimeInterval(-86_400), attempt: .distantPast)
        GeoIPStubURLProtocol.register(path: databasePath(month: month)) { request in
            (
                HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["ETag": "\"v2\""])!,
                cnGzip
            )
        }

        #expect(await service.countryCode(forIPv4Address: "1.0.0.1") == "CN")
        #expect(GeoIPStubURLProtocol.requestCount() == 1)
    }

    @Test func failedRefreshKeepsTheLoadedIndex() async throws {
        GeoIPStubURLProtocol.reset()
        let directory = freshCache()
        let month = monthString()
        try writeCache(directory, gzip: auGzip, release: month, success: Date(), attempt: .distantPast)
        let service = GeoIPService(
            cacheDirectory: directory,
            session: GeoIPStubURLProtocol.makeSession(),
            configuration: configuration(.daily))

        #expect(await service.countryCode(forIPv4Address: "1.0.0.1") == "AU")

        try writeCache(
            directory, gzip: auGzip, release: month,
            success: Date().addingTimeInterval(-86_400), attempt: .distantPast)

        // No handler: both the current and previous month 404.
        #expect(await service.countryCode(forIPv4Address: "1.0.0.1") == "AU")
        #expect(GeoIPStubURLProtocol.requestCount() == 2)
    }

    @Test func onStartupChecksOnlyOncePerProcess() async throws {
        GeoIPStubURLProtocol.reset()
        let directory = freshCache()
        let month = monthString()
        try writeCache(directory, gzip: auGzip, release: month, success: Date(), attempt: Date())
        var configuration = configuration(.onStartup)
        configuration.minimumRetryInterval = 3_600
        let service = GeoIPService(
            cacheDirectory: directory,
            session: GeoIPStubURLProtocol.makeSession(),
            configuration: configuration)

        #expect(await service.countryCode(forIPv4Address: "1.0.0.1") == "AU")

        try writeCache(
            directory, gzip: auGzip, release: month,
            success: Date().addingTimeInterval(-86_400), attempt: .distantPast)
        GeoIPStubURLProtocol.register(path: databasePath(month: month)) { request in
            (
                HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!,
                cnGzip
            )
        }

        #expect(await service.countryCode(forIPv4Address: "1.0.0.1") == "AU")
        #expect(GeoIPStubURLProtocol.requestCount() == 0)
    }

    private func configuration(_ frequency: GeoIPRefreshFrequency) -> GeoIPServiceConfiguration {
        var configuration = GeoIPServiceConfiguration()
        configuration.refreshFrequency = frequency
        configuration.minimumRetryInterval = 0
        return configuration
    }

    private func freshCache() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("geoip-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func monthString(_ date: Date = Date()) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year!, parts.month!)
    }

    private func databasePath(month: String) -> String {
        "/free/dbip-country-lite-\(month).csv.gz"
    }

    private func writeCache(
        _ directory: URL,
        gzip: Data,
        release: String,
        success: Date,
        attempt: Date
    ) throws {
        try gzip.write(to: directory.appendingPathComponent("dbip-country-lite.csv.gz"))
        let meta: [String: Any] = [
            "downloadedRelease": release,
            "lastSuccess": success.timeIntervalSinceReferenceDate,
            "lastAttempt": attempt.timeIntervalSinceReferenceDate,
            "etag": "\"v1\"",
        ]
        try JSONSerialization.data(withJSONObject: meta)
            .write(to: directory.appendingPathComponent("dbip-country-lite.meta.json"))
    }
}
