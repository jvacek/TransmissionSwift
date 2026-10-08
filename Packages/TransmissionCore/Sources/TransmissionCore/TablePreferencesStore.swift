import Foundation

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
