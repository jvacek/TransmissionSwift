import Foundation

public enum TransmissionError: Error, Sendable, Equatable {
    /// HTTP 401 — wrong or missing Basic-auth credentials.
    case unauthorized
    /// Transport-level failure (connection refused, timeout, DNS, …).
    case network(URLError)
    /// The response body could not be decoded as the expected JSON shape.
    case decoding(String)
    /// The daemon answered but reported failure — a non-`success` `result`
    /// string, an unexpected HTTP status, or a 409 that persisted after
    /// refreshing the session ID.
    case serverError(String)
    /// `torrent-add` returned a `torrent-duplicate` result — the torrent is
    /// already present on the daemon. The associated value is the torrent name.
    case torrentDuplicate(name: String)
}

extension TransmissionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "The server rejected the username or password."
        case .network(let urlError):
            return urlError.localizedDescription
        case .decoding(let detail):
            return "Could not read the server's response: \(detail)"
        case .serverError(let message):
            return "The server reported an error: \(message)"
        case .torrentDuplicate(let name):
            return "\u{201C}\(name)\u{201D} is already in your list."
        }
    }
}
