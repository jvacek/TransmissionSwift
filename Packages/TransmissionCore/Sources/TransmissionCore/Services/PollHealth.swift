// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// Whether a service's poll loop is currently succeeding.
public enum PollHealth: Sendable, Equatable {
    case ok
    case failing
}

/// Optional capability: a service that can report its poll health. The store
/// uses it to show a reconnecting indicator without changing the connection
/// state or discarding the last snapshot.
public protocol PollHealthReporting: Sendable {
    func pollHealth() async -> AsyncStream<PollHealth>
}
