import AppIntents

/// Makes the core actions available to Siri and Spotlight without the user
/// building a shortcut first.
struct TransmissionSwiftShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .blue }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetServersIntent(),
            phrases: [
                "Get my Transmission servers in \(.applicationName)",
                "List my servers in \(.applicationName)",
            ],
            shortTitle: "Get Servers",
            systemImageName: "server.rack")
        AppShortcut(
            intent: GetServerStatsIntent(),
            phrases: [
                "Get Transmission server stats in \(.applicationName)",
                "Get server stats in \(.applicationName)",
            ],
            shortTitle: "Server Stats",
            systemImageName: "chart.bar")
        AppShortcut(
            intent: GetFreeSpaceIntent(),
            phrases: ["Get free space in \(.applicationName)"],
            shortTitle: "Free Space",
            systemImageName: "internaldrive")
        AppShortcut(
            intent: PauseTorrentsIntent(),
            phrases: [
                "Pause torrents in \(.applicationName)",
                "Pause all torrents in \(.applicationName)",
            ],
            shortTitle: "Pause Torrents",
            systemImageName: "pause")
        AppShortcut(
            intent: ResumeTorrentsIntent(),
            phrases: [
                "Resume torrents in \(.applicationName)",
                "Resume all torrents in \(.applicationName)",
            ],
            shortTitle: "Resume Torrents",
            systemImageName: "play")
    }
}
