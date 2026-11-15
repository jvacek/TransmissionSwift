// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Synchronization

/// Persistence for the table's sort preference. A seam so `TorrentListModel`
/// can be exercised without touching the shared `UserDefaults`.
public protocol TablePreferencesStoring: Sendable {
    var tablePreferences: TablePreferences { get nonmutating set }
}

/// The production store: the sort preference encoded in `UserDefaults`.
public struct UserDefaultsTablePreferencesStore: TablePreferencesStoring {
    public init() {}

    public var tablePreferences: TablePreferences {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: PreferenceKeys.tablePreferencesSort),
                let decoded = try? JSONDecoder().decode(TablePreferences.self, from: data)
            else { return TablePreferences() }
            return decoded
        }
        nonmutating set {
            guard let encoded = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(encoded, forKey: PreferenceKeys.tablePreferencesSort)
        }
    }
}

/// A sort preference that lives only as long as the store: tests, and snapshot
/// replay, where clicking a header must work but never touch the user's saved
/// sort.
public final class InMemoryTablePreferencesStore: TablePreferencesStoring {
    private let value: Mutex<TablePreferences>

    public init(_ initial: TablePreferences = TablePreferences()) {
        value = Mutex(initial)
    }

    public var tablePreferences: TablePreferences {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }
}
