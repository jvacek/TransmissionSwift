import Foundation
import Synchronization
import Testing

@testable import TransmissionRPC

private let sessionIdHeader = "X-Transmission-Session-Id"

/// Real `session-get` response captured from transmission-daemon 4.1.2
/// (see Fixtures/ — recapture with curl if the daemon version changes).
private func successFixture() throws -> Data {
    let url = try #require(
        Bundle.module.url(
            forResource: "session-get-success", withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func makeClient(host: String, credentials: Credentials? = nil) -> URLSessionTransmissionClient {
    URLSessionTransmissionClient(
        rpcURL: URL(string: "http://\(host)/transmission/rpc")!,
        credentials: credentials,
        urlSession: StubURLProtocol.makeURLSession()
    )
}

@Suite("URLSessionTransmissionClient")
struct URLSessionTransmissionClientTests {

    @Test("sessionGet decodes version fields on 200")
    func happyPath() async throws {
        let host = "happy-path.test"
        let fixture = try successFixture()
        StubURLProtocol.register(host: host) { request in
            (makeHTTPResponse(url: request.url!, statusCode: 200), fixture)
        }

        let info = try await makeClient(host: host).sessionGet()

        #expect(info.version == "4.1.2 (f234716f3e)")
        #expect(info.rpcVersion == 19)
        #expect(info.rpcVersionMinimum == 14)
    }

    @Test("sessionGet retries once on 409, echoing the offered session ID")
    func handshake() async throws {
        let host = "handshake.test"
        let fixture = try successFixture()
        let recorded = Mutex<[URLRequest]>([])
        StubURLProtocol.register(host: host) { request in
            let attempt = recorded.withLock { requests in
                requests.append(request)
                return requests.count
            }
            if attempt == 1 {
                return (
                    makeHTTPResponse(
                        url: request.url!, statusCode: 409,
                        headers: [sessionIdHeader: "fresh-session-id"]),
                    Data("<h1>409: Conflict</h1>".utf8)
                )
            }
            return (makeHTTPResponse(url: request.url!, statusCode: 200), fixture)
        }

        let info = try await makeClient(host: host).sessionGet()

        #expect(info.rpcVersion == 19)
        let requests = recorded.withLock { $0 }
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: sessionIdHeader) == nil)
        #expect(requests[1].value(forHTTPHeaderField: sessionIdHeader) == "fresh-session-id")
    }

    @Test("session ID survives across calls — no second handshake")
    func sessionIdReused() async throws {
        let host = "session-reuse.test"
        let fixture = try successFixture()
        let recorded = Mutex<[URLRequest]>([])
        StubURLProtocol.register(host: host) { request in
            recorded.withLock { $0.append(request) }
            if request.value(forHTTPHeaderField: sessionIdHeader) == "sticky-id" {
                return (makeHTTPResponse(url: request.url!, statusCode: 200), fixture)
            }
            return (
                makeHTTPResponse(
                    url: request.url!, statusCode: 409, headers: [sessionIdHeader: "sticky-id"]),
                Data()
            )
        }
        let client = makeClient(host: host)

        _ = try await client.sessionGet()
        _ = try await client.sessionGet()

        // 409+retry on the first call, a single request on the second.
        #expect(recorded.withLock { $0.count } == 3)
    }

    @Test("sessionGet throws unauthorized on 401")
    func unauthorized() async throws {
        let host = "unauthorized.test"
        StubURLProtocol.register(host: host) { request in
            (
                makeHTTPResponse(
                    url: request.url!, statusCode: 401,
                    headers: ["WWW-Authenticate": "Basic realm=\"Transmission\""]),
                Data("<h1>401: Unauthorized</h1>".utf8)
            )
        }
        let client = makeClient(
            host: host, credentials: Credentials(username: "dev", password: "wrong"))

        await #expect(throws: TransmissionError.unauthorized) {
            try await client.sessionGet()
        }
    }

    @Test("credentials are sent as HTTP Basic auth")
    func basicAuthHeader() async throws {
        let host = "basic-auth.test"
        let fixture = try successFixture()
        let recorded = Mutex<[URLRequest]>([])
        StubURLProtocol.register(host: host) { request in
            recorded.withLock { $0.append(request) }
            return (makeHTTPResponse(url: request.url!, statusCode: 200), fixture)
        }
        let client = makeClient(
            host: host, credentials: Credentials(username: "dev", password: "devpass"))

        _ = try await client.sessionGet()

        let expected = "Basic \(Data("dev:devpass".utf8).base64EncodedString())"
        let authorization = recorded.withLock { $0.first?.value(forHTTPHeaderField: "Authorization") }
        #expect(authorization == expected)
    }

    @Test("sessionGet throws decoding error on malformed JSON")
    func malformedJSON() async throws {
        let host = "malformed.test"
        StubURLProtocol.register(host: host) { request in
            (makeHTTPResponse(url: request.url!, statusCode: 200), Data("not json {".utf8))
        }

        do {
            _ = try await makeClient(host: host).sessionGet()
            Issue.record("Expected a decoding error")
        } catch {
            guard case .decoding = error else {
                Issue.record("Expected .decoding, got \(error)")
                return
            }
        }
    }

    @Test("sessionGet surfaces a non-success result string as serverError")
    func resultFailure() async throws {
        let host = "result-failure.test"
        let body = Data(#"{"result":"no such method","arguments":{}}"#.utf8)
        StubURLProtocol.register(host: host) { request in
            (makeHTTPResponse(url: request.url!, statusCode: 200), body)
        }

        await #expect(throws: TransmissionError.serverError("no such method")) {
            try await makeClient(host: "result-failure.test").sessionGet()
        }
    }

    @Test("persistent 409 fails instead of retrying forever")
    func persistent409() async throws {
        let host = "persistent-409.test"
        let recorded = Mutex<Int>(0)
        StubURLProtocol.register(host: host) { request in
            recorded.withLock { $0 += 1 }
            return (
                makeHTTPResponse(
                    url: request.url!, statusCode: 409, headers: [sessionIdHeader: "ignored-anyway"]),
                Data()
            )
        }

        do {
            _ = try await makeClient(host: host).sessionGet()
            Issue.record("Expected a serverError")
        } catch {
            guard case .serverError = error else {
                Issue.record("Expected .serverError, got \(error)")
                return
            }
        }
        #expect(recorded.withLock { $0 } == 2)
    }
}
