import SwiftUI
import TransmissionCore

/// SwiftUI previews for the reworked preferences panes. Kept in a small file
/// separate from the ~1000-line `PreferencesView.swift` — the `#Preview` macro
/// is sensitive to per-file type-check complexity, and the sidebar-based
/// `PreferencesView` is too large to preview; these render the individual
/// session panes instead.
///
/// `previewStore` is `@MainActor`; previews run on the main actor so building it
/// at file scope is safe. The store starts against a mock whose `sessionSettings`
/// returns `SessionSettings.sample`, so the connected previews render populated
/// forms; the disconnected preview shows the gate.

private let previewStore: TorrentStore = {
    let store = TorrentStore(service: MockTorrentService())
    store.simulateConnection(.connected)
    return store
}()

private let disconnectedPreviewStore: TorrentStore = {
    let store = TorrentStore(service: MockTorrentService())
    store.simulateConnection(.disconnected(reason: "offline"))
    // The store's init task auto-connects when the mock stream yields; pausing
    // polling before the task runs keeps it in the disconnected state.
    store.pausePolling()
    return store
}()

#Preview("Speed — Connected") {
    SpeedPrefsPane()
        .environment(previewStore)
        .frame(width: 480, height: 540)
}

#Preview("Network — Connected") {
    NetworkPrefsPane()
        .environment(previewStore)
        .frame(width: 480, height: 640)
}

#Preview("Seeding — Connected") {
    SeedingPrefsPane()
        .environment(previewStore)
        .frame(width: 480, height: 320)
}

#Preview("Session — Not Connected") {
    NetworkPrefsPane()
        .environment(disconnectedPreviewStore)
        .frame(width: 480, height: 360)
}

#Preview("Preferences — Connected") {
    PreferencesView()
        .environment(ServerProfileStore(fileURL: FileManager.default.temporaryDirectory))
        .environment(previewStore)
        .environment(FaviconStore())
        .environment(TagColorStore())
        .frame(width: 700, height: 560)
}

// MARK: - Other panes

private let previewProfileStore: ServerProfileStore = {
    let store = ServerProfileStore(
        fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("servers-preview-\(UUID().uuidString).json"))
    try? store.add(ServerProfile(label: "Home NAS", host: "192.168.1.2", port: 9091))
    try? store.add(ServerProfile(label: "Seedbox", host: "seedbox.example.com", port: 9091))
    try? store.setActive(store.profiles.first!.id)
    return store
}()

#Preview("General") {
    GeneralPrefsPane()
        .environment(FaviconStore())
        .frame(width: 480, height: 480)
}

#Preview("Servers") {
    ServersPrefsPane()
        .environment(previewProfileStore)
        .environment(previewStore)
        .frame(width: 700, height: 480)
}

#Preview("Remote") {
    RemotePrefsPane()
        .frame(width: 480, height: 400)
}

#Preview("Updates") {
    UpdatesPrefsPane()
        .frame(width: 480, height: 240)
}

#Preview("Developer — Connected") {
    DeveloperPrefsPane()
        .environment(previewStore)
        .environment(TagColorStore())
        .frame(minWidth: 620, minHeight: 520)
}
