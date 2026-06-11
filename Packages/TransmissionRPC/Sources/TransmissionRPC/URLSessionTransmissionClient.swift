import Foundation
import OSLog

/// Wire-level log of every RPC exchange, for debugging server connections.
/// Stream it live with:
///
///     log stream --level debug --predicate 'subsystem == "net.jvacek.TransmissionSwift"'
///
/// or filter Console.app by that subsystem. Auth headers are never logged.
private let logger = Logger(subsystem: "net.jvacek.TransmissionSwift", category: "rpc")

public struct Credentials: Sendable, Equatable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

/// Speaks Transmission's legacy RPC protocol (`{"method", "arguments", "tag"}`
/// envelope, kebab-case keys) — supported by every daemon version, unlike the
/// JSON-RPC 2.0 protocol introduced in Transmission 4.1.
///
/// An actor because the CSRF session ID is mutable state shared across calls:
/// the daemon answers 409 with a fresh `X-Transmission-Session-Id` header
/// whenever ours is missing or stale, and we must retry exactly once.
public actor URLSessionTransmissionClient: TransmissionClient {
    private static let sessionIdHeader = "X-Transmission-Session-Id"

    private let rpcURL: URL
    private let credentials: Credentials?
    private let urlSession: URLSession
    private var sessionId: String?

    /// - Parameters:
    ///   - rpcURL: Full endpoint URL, e.g. `http://host:9091/transmission/rpc`.
    ///   - urlSession: Injectable so tests can supply a stubbed configuration.
    public init(rpcURL: URL, credentials: Credentials? = nil, urlSession: URLSession = .shared) {
        self.rpcURL = rpcURL
        self.credentials = credentials
        self.urlSession = urlSession
    }

    public func sessionGet() async throws(TransmissionError) -> SessionInfo {
        try await send(method: "session-get", arguments: EmptyArguments())
    }

    public func torrentGet(fields: [String], ids: [Int]?) async throws(TransmissionError) -> TorrentGetResponse {
        try await send(method: "torrent-get", arguments: TorrentGetArguments(fields: fields, ids: ids))
    }

    public func torrentAction(_ method: String, ids: [Int]) async throws(TransmissionError) {
        try await sendAction(method: method, arguments: TorrentIDArguments(ids: ids))
    }

    public func torrentRemove(ids: [Int], deleteLocalData: Bool) async throws(TransmissionError) {
        try await sendAction(
            method: "torrent-remove",
            arguments: TorrentRemoveArguments(ids: ids, deleteLocalData: deleteLocalData)
        )
    }

    public func torrentSet(_ args: TorrentSetArguments) async throws(TransmissionError) {
        try await sendAction(method: "torrent-set", arguments: args)
    }

    public func torrentAdd(_ args: TorrentAddArguments) async throws(TransmissionError) -> TorrentAddResponse {
        try await send(method: "torrent-add", arguments: args)
    }

    public func sessionSet(_ args: SessionSetArguments) async throws(TransmissionError) {
        try await sendAction(method: "session-set", arguments: args)
    }

    // MARK: - Request plumbing

    private struct RPCRequest<Arguments: Encodable>: Encodable {
        let method: String
        let arguments: Arguments
    }

    private struct RPCResponse<Arguments: Decodable>: Decodable {
        let result: String
        let arguments: Arguments?
    }

    private struct RPCResultOnly: Decodable {
        let result: String
    }

    private struct EmptyArguments: Encodable {}
    private struct VoidReply: Decodable {}

    /// Sends a mutation RPC that returns no useful arguments — only checks for "success".
    private func sendAction<Arguments: Encodable>(
        method: String,
        arguments: Arguments
    ) async throws(TransmissionError) {
        let _: VoidReply = try await send(method: method, arguments: arguments)
    }

    private func send<Arguments: Encodable, Reply: Decodable>(
        method: String,
        arguments: Arguments
    ) async throws(TransmissionError) -> Reply {
        let body: Data
        do {
            body = try JSONEncoder().encode(RPCRequest(method: method, arguments: arguments))
        } catch {
            throw .decoding("Failed to encode request for \(method): \(error)")
        }

        var (data, response) = try await perform(body: body)

        // Stale or missing session ID: adopt the one the daemon offers, retry once.
        if response.statusCode == 409 {
            guard let freshId = response.value(forHTTPHeaderField: Self.sessionIdHeader) else {
                throw .serverError("409 Conflict without a \(Self.sessionIdHeader) header")
            }
            logger.debug("409 handshake: adopted fresh session ID, retrying once")
            sessionId = freshId
            (data, response) = try await perform(body: body)
        }

        switch response.statusCode {
        case 200...299:
            break
        case 401:
            throw .unauthorized
        case 409:
            throw .serverError("Session ID handshake failed: still 409 after refresh")
        default:
            // Include what the server actually sent — proxies and login pages
            // answer with HTML that explains a lot more than the status code.
            throw .serverError("HTTP \(response.statusCode): \(Self.snippet(data, limit: 300))")
        }

        // Check the daemon's verdict before decoding the typed arguments, so a
        // daemon-reported error surfaces as serverError, not a decoding failure.
        do {
            let verdict = try JSONDecoder().decode(RPCResultOnly.self, from: data)
            guard verdict.result == "success" else {
                throw TransmissionError.serverError(verdict.result)
            }
            let envelope = try JSONDecoder().decode(RPCResponse<Reply>.self, from: data)
            guard let reply = envelope.arguments else {
                throw TransmissionError.decoding("Response for \(method) is missing the arguments object")
            }
            return reply
        } catch let error as TransmissionError {
            throw error
        } catch {
            throw .decoding("\(error) — body was: \(Self.snippet(data, limit: 300))")
        }
    }

    private func perform(body: Data) async throws(TransmissionError) -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let sessionId {
            request.setValue(sessionId, forHTTPHeaderField: Self.sessionIdHeader)
        }
        if let credentials {
            let encoded = Data("\(credentials.username):\(credentials.password)".utf8)
                .base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }

        logger.debug(
            "→ POST \(self.rpcURL.absoluteString, privacy: .public) (\(body.count) bytes, session-id: \(self.sessionId != nil ? "set" : "none", privacy: .public))"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch let urlError as URLError {
            logger.error(
                "✗ \(self.rpcURL.absoluteString, privacy: .public) failed: \(urlError.localizedDescription, privacy: .public) (URLError \(urlError.code.rawValue))"
            )
            throw .network(urlError)
        } catch {
            logger.error("✗ \(self.rpcURL.absoluteString, privacy: .public) failed: \(error, privacy: .public)")
            throw .network(URLError(.unknown))
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error(
                "✗ \(self.rpcURL.absoluteString, privacy: .public): non-HTTP response \(type(of: response), privacy: .public)"
            )
            throw .serverError("Received a non-HTTP response")
        }
        logger.debug(
            "← HTTP \(httpResponse.statusCode) (\(data.count) bytes) from \(self.rpcURL.absoluteString, privacy: .public)"
        )
        logger.debug("← body: \(Self.snippet(data), privacy: .public)")
        return (data, httpResponse)
    }

    private static func snippet(_ data: Data, limit: Int = 2048) -> String {
        guard !data.isEmpty else { return "<empty body>" }
        let text = String(decoding: data.prefix(limit), as: UTF8.self)
        return data.count > limit ? "\(text)… [truncated, \(data.count) bytes total]" : text
    }
}
