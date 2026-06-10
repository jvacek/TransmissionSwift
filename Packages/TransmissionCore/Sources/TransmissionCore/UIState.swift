import Foundation

/// Lifecycle of the active server connection. Drives empty / skeleton / error
/// surfaces in the main window per `doc/ui-buildout.md` slice 6.
public enum ConnectionState: Sendable, Equatable {
    case connecting
    case connected
    case disconnected(reason: String)
}

/// One of the five tabs in the right-pane inspector.
public enum InspectorTab: String, Hashable, Sendable, CaseIterable, Codable {
    case general, files, peers, trackers, options
}
