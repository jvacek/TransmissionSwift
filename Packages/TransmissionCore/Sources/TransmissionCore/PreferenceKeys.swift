import Foundation

/// `UserDefaults` keys for the app preferences. The app binds most of these with
/// `@AppStorage`; `TransmissionCore` reads a few directly (poll intervals, the
/// remove-confirmation pref, tag colours). Routing every key through here stops
/// the writer and the reader from drifting on a typo, which fails silently.
public enum PreferenceKeys {
    // Downloads
    public static let showAddDialogBeforeAdding = "showAddDialogBeforeAdding"
    public static let deleteTorrentFileAfterAdding = "deleteTorrentFileAfterAdding"

    // General
    public static let startMinimized = "startMinimized"
    public static let badgeAppIcon = "badgeAppIcon"
    public static let confirmRemove = "confirmRemove"
    public static let showDonateButton = "showDonateButton"
    public static let showBugReportButton = "showBugReportButton"
    public static let sendCrashReports = "sendCrashReports"
    public static let pollingIntervalSeconds = "pollingIntervalSeconds"
    public static let freeSpaceIntervalSeconds = "freeSpaceIntervalSeconds"
    public static let fetchTrackerFavicons = "fetchTrackerFavicons"

    // Updates
    public static let includePrereleases = "includePrereleases"
    /// Owned by Sparkle, not us; named here only so the reference isn't a bare
    /// literal in the Updates pane.
    public static let sparkleAutoUpdateChecks = "SUEnableAutomaticChecks"

    // Window / navigation
    public static let inspectorWidth = "inspectorWidth"
    public static let inspectorVisible = "inspectorVisible"
    public static let prefsPendingNavTab = "prefsPendingNavTab"

    // Sidebar section expansion
    public static let sidebarStatusExpanded = "sidebar.section.expanded.status"
    public static let sidebarTrackersExpanded = "sidebar.section.expanded.trackers"
    public static let sidebarFoldersExpanded = "sidebar.section.expanded.folders"
    public static let sidebarLabelsExpanded = "sidebar.section.expanded.labels"

    // Components
    public static let serverPathHelpExpanded = "serverPathHelpExpanded"

    // Table / tags
    public static let tablePreferencesSort = "tablePreferencesSort"
    public static let tagColors = "tagColors"
}
