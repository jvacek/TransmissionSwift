import Foundation
import Observation

/// A pending "open this torrent in the app" request from an App Intent.
/// Intents run outside the SwiftUI object graph, so they hand navigation off
/// through this bus; `MainWindow` observes it and applies it.
struct OpenRequest: Equatable, Sendable {
    let serverID: UUID?
    let torrentID: Int

    init(serverID: UUID?, torrentID: Int) {
        self.serverID = serverID
        self.torrentID = torrentID
    }

    /// Parses a `transmissionswift://<serverUUID>/<torrentID>` deep link, the
    /// URL form of `TorrentEntity`. Nil for anything else.
    init?(deepLink url: URL) {
        guard url.scheme == "transmissionswift",
            let host = url.host,
            let serverID = UUID(uuidString: host),
            let torrentID = Int(url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        else { return nil }
        self.init(serverID: serverID, torrentID: torrentID)
    }
}

@MainActor
@Observable
final class OpenRequestBus {
    static let shared = OpenRequestBus()

    /// How long a request stays pending before it's dropped. It only has to
    /// outlive the server switch plus one poll.
    private static let timeToLive: TimeInterval = 30

    var request: OpenRequest? {
        didSet { expiresAt = request.map { _ in Date().addingTimeInterval(Self.timeToLive) } }
    }
    private var expiresAt: Date?

    /// The pending request, or nil once it has aged out. A request whose torrent
    /// never appears is dropped rather than lingering to fire on a later poll.
    func pending(now: Date = Date()) -> OpenRequest? {
        guard let request else { return nil }
        guard let expiresAt, now < expiresAt else {
            self.request = nil
            return nil
        }
        return request
    }

    private init() {}
}
