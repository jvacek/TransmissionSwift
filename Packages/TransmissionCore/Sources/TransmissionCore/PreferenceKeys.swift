import Foundation

/// `UserDefaults` keys for the app preferences that `TorrentStore` reads
/// directly. The app registers the defaults and binds its toggles with
/// `@AppStorage`; keeping the literal in one place stops the three from drifting.
public enum PreferenceKeys {
    public static let showAddDialogBeforeAdding = "showAddDialogBeforeAdding"
    public static let deleteTorrentFileAfterAdding = "deleteTorrentFileAfterAdding"
}
