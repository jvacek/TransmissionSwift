import Foundation
import Testing
import os

@testable import TransmissionCore

private let testLogger = Logger(subsystem: "net.jvacek.TransmissionSwift.Tests", category: "FaviconServiceTests")

private enum StubError: Error { case offline }

/// Minimal view of the on-disk meta, enough to tell a positive entry (non-empty
/// `sourceURL`) from a negative one.
private struct MetaProbe: Decodable { let sourceURL: String }

private final class TestStubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let handlers = OSAllocatedUnfairLock<[String: Handler]>(initialState: [:])
    private static let requestedPaths = OSAllocatedUnfairLock<Set<String>>(initialState: [])

    static func register(path: String, handler: @escaping Handler) {
        handlers.withLock { $0[path] = handler }
        testLogger.debug("REGISTER \(path, privacy: .public)")
    }

    static func reset() {
        handlers.withLock { $0.removeAll() }
        requestedPaths.withLock { $0.removeAll() }
        testLogger.debug("RESET")
    }

    static func requested(_ path: String) -> Bool {
        requestedPaths.withLock { $0.contains(path) }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let path = url.path().isEmpty ? "/" : url.path()
        testLogger.debug("LOAD \(path, privacy: .public) count=\(Self.handlers.withLock { $0.count })")
        _ = Self.requestedPaths.withLock { $0.insert(path) }
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

@Suite(.serialized)
struct FaviconServiceTests {
    let session: URLSession
    let svg =
        #"<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"><rect width="1" height="1"/></svg>"#
        .data(using: .utf8)!
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    init() {
        session = TestStubURLProtocol.makeSession()
    }

    private func freshService(configuration: FaviconServiceConfiguration = .default) -> (FaviconService, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("favicon-test-\(UUID().uuidString)")
        return (FaviconService(cacheDirectory: dir, session: session, configuration: configuration), dir)
    }

    private func response(_ url: URL, _ code: Int, _ headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    @Test("Prefers the apple-touch-icon declared in HTML over low-res fallbacks")
    func htmlLinkPriority() async {
        TestStubURLProtocol.reset()
        TestStubURLProtocol.register(path: "/") { req in
            let html =
                #"<link rel="icon" href="/custom.svg" type="image/svg+xml"><link rel="apple-touch-icon" href="/at.png" sizes="180x180">"#
            return (self.response(req.url!, 200, ["Content-Type": "text/html"]), html.data(using: .utf8)!)
        }
        TestStubURLProtocol.register(path: "/at.png") { _ in
            (self.response(URL(string: "https://example.com/at.png")!, 404), Data())
        }
        TestStubURLProtocol.register(path: "/custom.svg") { _ in
            (
                self.response(URL(string: "https://example.com/custom.svg")!, 200, ["Content-Type": "image/svg+xml"]),
                self.svg
            )
        }

        let (service, _) = freshService()
        let data = await service.icon(for: "example.com")

        #expect(data == svg)
        #expect(TestStubURLProtocol.requested("/custom.svg"))
        #expect(!TestStubURLProtocol.requested("/favicon.ico"))
    }

    @Test("Falls back to static paths when HTML has no icon links")
    func staticFallback() async {
        TestStubURLProtocol.reset()
        TestStubURLProtocol.register(path: "/") { req in
            (self.response(req.url!, 200, ["Content-Type": "text/html"]), "<html></html>".data(using: .utf8)!)
        }
        TestStubURLProtocol.register(path: "/apple-touch-icon.png") { _ in
            (self.response(URL(string: "https://example.com/apple-touch-icon.png")!, 404), Data())
        }
        TestStubURLProtocol.register(path: "/favicon.ico") { _ in
            (
                self.response(URL(string: "https://example.com/favicon.ico")!, 200, ["Content-Type": "image/x-icon"]),
                self.png
            )
        }

        let (service, _) = freshService()
        let data = await service.icon(for: "example.com")

        #expect(data == png)
        #expect(TestStubURLProtocol.requested("/favicon.ico"))
    }

    @Test("Rejects non-image responses")
    func rejectsHtml() async {
        TestStubURLProtocol.reset()
        TestStubURLProtocol.register(path: "/") { req in
            (self.response(req.url!, 404), Data())
        }
        TestStubURLProtocol.register(path: "/favicon.ico") { _ in
            (
                self.response(URL(string: "https://example.com/favicon.ico")!, 200, ["Content-Type": "text/html"]),
                "<html>not an icon</html>".data(using: .utf8)!
            )
        }

        let (service, _) = freshService()
        let data = await service.icon(for: "example.com")

        #expect(data == nil)
    }

    @Test("Writes and reuses the disk cache")
    func cachesToDisk() async {
        TestStubURLProtocol.reset()
        TestStubURLProtocol.register(path: "/") { req in
            (self.response(req.url!, 404), Data())
        }
        TestStubURLProtocol.register(path: "/favicon.ico") { _ in
            (
                self.response(URL(string: "https://example.com/favicon.ico")!, 200, ["Content-Type": "image/x-icon"]),
                self.png
            )
        }

        let (service, cacheDir) = freshService()
        _ = await service.icon(for: "example.com")

        let bin = cacheDir.appendingPathComponent("example.com.bin")
        let meta = cacheDir.appendingPathComponent("example.com.meta.json")
        #expect(FileManager.default.fileExists(atPath: bin.path()))
        #expect(FileManager.default.fileExists(atPath: meta.path()))

        TestStubURLProtocol.reset()
        let cached = await service.icon(for: "example.com")
        #expect(cached == png)
        #expect(!TestStubURLProtocol.requested("/favicon.ico"))
    }

    @Test("Reads the disk cache from a fresh service instance (survives restart)")
    func cacheSurvivesRestart() async {
        TestStubURLProtocol.reset()
        TestStubURLProtocol.register(path: "/") { req in
            (self.response(req.url!, 404), Data())
        }
        TestStubURLProtocol.register(path: "/favicon.ico") { _ in
            (
                self.response(URL(string: "https://example.com/favicon.ico")!, 200, ["Content-Type": "image/x-icon"]),
                self.png
            )
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("favicon-restart-\(UUID().uuidString)")
        let first = FaviconService(cacheDirectory: dir, session: session)
        _ = await first.icon(for: "example.com")

        TestStubURLProtocol.reset()
        let second = FaviconService(cacheDirectory: dir, session: TestStubURLProtocol.makeSession())
        let cached = await second.icon(for: "example.com")

        #expect(cached == png)
        #expect(!TestStubURLProtocol.requested("/favicon.ico"))
    }

    @Test("Revalidates the recorded source URL instead of re-running discovery")
    func revalidation304() async {
        TestStubURLProtocol.reset()
        TestStubURLProtocol.register(path: "/") { req in
            (self.response(req.url!, 200, ["Content-Type": "text/html"]), Data("<html></html>".utf8))
        }
        TestStubURLProtocol.register(path: "/favicon.ico") { req in
            (
                self.response(req.url!, 200, ["Content-Type": "image/x-icon", "ETag": "\"v1\""]),
                self.png
            )
        }

        let (service, _) = freshService()
        let first = await service.icon(for: "example.com")
        #expect(first == png)

        // Re-discovery would now find a different icon; revalidation must not look.
        TestStubURLProtocol.reset()
        TestStubURLProtocol.register(path: "/favicon.ico") { req in
            (self.response(req.url!, 304), Data())
        }
        TestStubURLProtocol.register(path: "/") { req in
            let html = #"<link rel="icon" href="/custom.svg" type="image/svg+xml">"#
            return (self.response(req.url!, 200, ["Content-Type": "text/html"]), Data(html.utf8))
        }
        TestStubURLProtocol.register(path: "/custom.svg") { _ in
            (
                self.response(URL(string: "https://example.com/custom.svg")!, 200, ["Content-Type": "image/svg+xml"]),
                self.svg
            )
        }

        let revalidated = await service.icon(for: "example.com", forceRevalidate: true)

        #expect(revalidated == png)
        #expect(!TestStubURLProtocol.requested("/custom.svg"))
    }

    @Test("Negative-caches a host that serves no icon")
    func negativeCache() async {
        TestStubURLProtocol.reset()
        TestStubURLProtocol.register(path: "/") { req in
            (self.response(req.url!, 200, ["Content-Type": "text/html"]), Data("<html></html>".utf8))
        }

        let (service, _) = freshService()
        let first = await service.icon(for: "example.com")
        #expect(first == nil)

        TestStubURLProtocol.reset()
        let second = await service.icon(for: "example.com")
        #expect(second == nil)
        #expect(!TestStubURLProtocol.requested("/favicon.ico"))
    }

    @Test("Re-queries once the negative cache expires")
    func negativeCacheExpiry() async {
        TestStubURLProtocol.reset()
        TestStubURLProtocol.register(path: "/") { req in
            (self.response(req.url!, 200, ["Content-Type": "text/html"]), Data("<html></html>".utf8))
        }

        var configuration = FaviconServiceConfiguration()
        configuration.negativeCacheInterval = 0
        let (service, _) = freshService(configuration: configuration)
        let first = await service.icon(for: "example.com")
        #expect(first == nil)

        TestStubURLProtocol.register(path: "/favicon.ico") { req in
            (self.response(req.url!, 200, ["Content-Type": "image/x-icon"]), self.png)
        }
        let second = await service.icon(for: "example.com")
        #expect(second == png)
    }

    @Test("Keeps the cached icon when revalidation has a transport failure")
    func transportFailureKeepsStale() async {
        TestStubURLProtocol.reset()
        TestStubURLProtocol.register(path: "/") { req in
            (self.response(req.url!, 200, ["Content-Type": "text/html"]), Data("<html></html>".utf8))
        }
        TestStubURLProtocol.register(path: "/favicon.ico") { req in
            (self.response(req.url!, 200, ["Content-Type": "image/x-icon"]), self.png)
        }

        let (service, _) = freshService(configuration: alwaysStaleConfiguration())
        let first = await service.icon(for: "example.com")
        #expect(first == png)

        // The recorded source is now unreachable. Re-discovery would find a
        // different icon, but a transport failure must keep the cached bytes.
        TestStubURLProtocol.reset()
        TestStubURLProtocol.register(path: "/favicon.ico") { _ in throw StubError.offline }
        TestStubURLProtocol.register(path: "/") { req in
            let html = #"<link rel="icon" href="/custom.svg" type="image/svg+xml">"#
            return (self.response(req.url!, 200, ["Content-Type": "text/html"]), Data(html.utf8))
        }
        TestStubURLProtocol.register(path: "/custom.svg") { _ in
            (
                self.response(URL(string: "https://example.com/custom.svg")!, 200, ["Content-Type": "image/svg+xml"]),
                self.svg
            )
        }

        let stale = await service.icon(for: "example.com")

        #expect(stale == png)
        #expect(TestStubURLProtocol.requested("/favicon.ico"))
        #expect(!TestStubURLProtocol.requested("/custom.svg"))
    }

    @Test("Falls through to discovery when the recorded source is gone")
    func httpFailureRediscovers() async {
        TestStubURLProtocol.reset()
        TestStubURLProtocol.register(path: "/") { req in
            (self.response(req.url!, 200, ["Content-Type": "text/html"]), Data("<html></html>".utf8))
        }
        TestStubURLProtocol.register(path: "/favicon.ico") { req in
            (self.response(req.url!, 200, ["Content-Type": "image/x-icon"]), self.png)
        }

        let (service, _) = freshService(configuration: alwaysStaleConfiguration())
        let first = await service.icon(for: "example.com")
        #expect(first == png)

        // The recorded source 404s, so discovery should run again and prefer
        // the SVG the HTML now links.
        TestStubURLProtocol.reset()
        TestStubURLProtocol.register(path: "/") { req in
            let html = #"<link rel="icon" href="/custom.svg" type="image/svg+xml">"#
            return (self.response(req.url!, 200, ["Content-Type": "text/html"]), Data(html.utf8))
        }
        TestStubURLProtocol.register(path: "/custom.svg") { _ in
            (
                self.response(URL(string: "https://example.com/custom.svg")!, 200, ["Content-Type": "image/svg+xml"]),
                self.svg
            )
        }

        let updated = await service.icon(for: "example.com")

        #expect(updated == svg)
        #expect(TestStubURLProtocol.requested("/custom.svg"))
    }

    @Test("Keeps the cached icon when discovery fails and does not negative-cache it")
    func discoveryFailureKeepsStale() async {
        TestStubURLProtocol.reset()
        TestStubURLProtocol.register(path: "/") { req in
            (self.response(req.url!, 200, ["Content-Type": "text/html"]), Data("<html></html>".utf8))
        }
        TestStubURLProtocol.register(path: "/favicon.ico") { req in
            (self.response(req.url!, 200, ["Content-Type": "image/x-icon"]), self.png)
        }

        let (service, dir) = freshService(configuration: alwaysStaleConfiguration())
        let first = await service.icon(for: "example.com")
        #expect(first == png)

        // Source gone and every discovery candidate now fails.
        TestStubURLProtocol.reset()
        TestStubURLProtocol.register(path: "/") { req in
            (self.response(req.url!, 200, ["Content-Type": "text/html"]), Data("<html></html>".utf8))
        }

        let stale = await service.icon(for: "example.com")

        #expect(stale == png)
        // The positive entry survives: sourceURL is still recorded, not cleared
        // to the empty string a negative entry would carry.
        let metaData = try? Data(contentsOf: dir.appendingPathComponent("example.com.meta.json"))
        let probe = metaData.flatMap { try? JSONDecoder().decode(MetaProbe.self, from: $0) }
        #expect(probe?.sourceURL == "https://example.com/favicon.ico")
    }

    @Test("Revalidation with a 200 replaces the cached bytes")
    func revalidationReplaces() async {
        TestStubURLProtocol.reset()
        TestStubURLProtocol.register(path: "/") { req in
            (self.response(req.url!, 200, ["Content-Type": "text/html"]), Data("<html></html>".utf8))
        }
        TestStubURLProtocol.register(path: "/favicon.ico") { req in
            (self.response(req.url!, 200, ["Content-Type": "image/x-icon"]), self.png)
        }

        let (service, dir) = freshService(configuration: alwaysStaleConfiguration())
        let first = await service.icon(for: "example.com")
        #expect(first == png)

        // The recorded source now serves a new icon. Discovery would still find
        // the old SVG link, so revalidation must win and refresh the bytes.
        TestStubURLProtocol.reset()
        TestStubURLProtocol.register(path: "/favicon.ico") { req in
            (self.response(req.url!, 200, ["Content-Type": "image/svg+xml"]), self.svg)
        }
        TestStubURLProtocol.register(path: "/") { req in
            let html = #"<link rel="icon" href="/stale.svg" type="image/svg+xml">"#
            return (self.response(req.url!, 200, ["Content-Type": "text/html"]), Data(html.utf8))
        }
        TestStubURLProtocol.register(path: "/stale.svg") { _ in
            (
                self.response(URL(string: "https://example.com/stale.svg")!, 200, ["Content-Type": "image/svg+xml"]),
                self.png
            )
        }

        let updated = await service.icon(for: "example.com")

        #expect(updated == svg)
        let onDisk = try? Data(contentsOf: dir.appendingPathComponent("example.com.bin"))
        #expect(onDisk == svg)
        #expect(!TestStubURLProtocol.requested("/stale.svg"))
    }

    /// Every entry is immediately stale, so a second call takes the
    /// revalidation branch rather than the freshness short-circuit.
    private func alwaysStaleConfiguration() -> FaviconServiceConfiguration {
        var configuration = FaviconServiceConfiguration()
        configuration.revalidationInterval = 0
        return configuration
    }
}
