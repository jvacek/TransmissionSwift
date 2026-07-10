import Foundation
import Testing
import os

@testable import TransmissionCore

private let testLogger = Logger(subsystem: "net.jvacek.TransmissionSwift.Tests", category: "FaviconServiceTests")

private final class TestStubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) -> (HTTPURLResponse, Data)

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
        let handler = Self.handlers.withLock { $0[path] }
        let (response, data) =
            handler?(request)
            ?? (HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: [:])!, Data())
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
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

    private func freshService() -> (FaviconService, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("favicon-test-\(UUID().uuidString)")
        return (FaviconService(cacheDirectory: dir, session: session), dir)
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

    @Test("Returns cached data on a 304 revalidation")
    func revalidation304() async {
        TestStubURLProtocol.reset()
        let firstLock = OSAllocatedUnfairLock<Bool>(initialState: true)
        TestStubURLProtocol.register(path: "/favicon.ico") { req in
            let isFirst = firstLock.withLock { (state: inout Bool) -> Bool in
                let value = state
                state = false
                return value
            }
            if isFirst {
                return (self.response(req.url!, 200, ["Content-Type": "image/x-icon", "ETag": "\"v1\""]), self.png)
            }
            return (self.response(req.url!, 304), Data())
        }

        let (service, _) = freshService()
        _ = await service.icon(for: "example.com")
        let revalidated = await service.icon(for: "example.com", forceRevalidate: true)

        #expect(revalidated == png)
    }
}
