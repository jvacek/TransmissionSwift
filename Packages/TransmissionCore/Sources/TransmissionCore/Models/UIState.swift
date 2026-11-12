// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Lifecycle of the active server connection. Drives empty / skeleton / error
/// surfaces in the main window.
public enum ConnectionState: Sendable, Equatable {
    case connecting
    /// Waiting for the macOS keychain access dialog before connecting.
    case awaitingKeychain
    case connected
    case disconnected(reason: String)

    /// True only for a live connection. Used to gate session-side settings
    /// that require a daemon round-trip.
    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

/// One of the five tabs in the right-pane inspector.
public enum InspectorTab: String, Hashable, Sendable, CaseIterable, Codable {
    case general, files, peers, trackers, options
}
