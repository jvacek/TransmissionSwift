import Foundation
import Observation

/// A pending "open this torrent in the app" request from an App Intent.
/// Intents run outside the SwiftUI object graph, so they hand navigation off
/// through this bus; `MainWindow` observes it and applies it.
struct OpenRequest: Equatable, Sendable {
    let serverID: UUID?
    let torrentID: Int
}

@MainActor
@Observable
final class OpenRequestBus {
    static let shared = OpenRequestBus()
    var request: OpenRequest?
    private init() {}
}
