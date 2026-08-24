import SwiftUI
import TransmissionCore

/// The unified window toolbar. Items grouped by purpose with `ToolbarSpacer`
/// between groups — the macOS 26 Liquid Glass convention. No coloured buttons:
/// all action items stay monochrome; status colour appears only in rows and
/// the status bar.
///
/// The server switcher lives in `MainWindow` (as a separate `.toolbar` item)
/// rather than here because `ToolbarContent` structs have more limited
/// `DynamicProperty` support than `View`, and mixing `@Environment` access for
/// two different stores breaks `@ToolbarContentBuilder` conditional inference.
struct MainToolbar: ToolbarContent {
    @Environment(TorrentStore.self) private var store

    var body: some ToolbarContent {
        // Group 1 — Add
        ToolbarItem(placement: .primaryAction) {
            Button("Add", systemImage: "plus") {
                store.openAddSheet()
            }
            .disabled(!store.actionsEnabled)
            .help("Add torrent file")
            .accessibilityIdentifier("toolbar.add")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Add Magnet", systemImage: "link") {
                store.openAddSheet(magnetMode: true)
            }
            .disabled(!store.actionsEnabled)
            .help("Add magnet link")
            .accessibilityIdentifier("toolbar.addMagnet")
        }

        ToolbarSpacer(.fixed)

        // Group 2 — selection actions
        ToolbarItem(placement: .primaryAction) {
            Button("Resume", systemImage: "play.fill") {
                Task { await store.start(Array(store.selectedTorrentIDs)) }
            }
            .disabled(!store.actionsEnabled || store.selectedTorrentIDs.isEmpty)
            .help("Resume selected torrents")
            .accessibilityIdentifier("toolbar.resume")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Pause", systemImage: "pause.fill") {
                Task { await store.stop(Array(store.selectedTorrentIDs)) }
            }
            .disabled(!store.actionsEnabled || store.selectedTorrentIDs.isEmpty)
            .help("Pause selected torrents")
            .accessibilityIdentifier("toolbar.pause")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Remove", systemImage: "trash", role: .destructive) {
                Task { await store.remove(Array(store.selectedTorrentIDs)) }
            }
            .disabled(!store.actionsEnabled || store.selectedTorrentIDs.isEmpty)
            .help("Remove selected torrents")
            .accessibilityIdentifier("toolbar.remove")
        }

        ToolbarSpacer(.flexible)

        // Group 3 — view toggles
        ToolbarItem(placement: .primaryAction) {
            Button {
                store.inspectorVisible.toggle()
            } label: {
                Label("Toggle Inspector", systemImage: "sidebar.right")
            }
            .help("Toggle inspector")
            .accessibilityIdentifier("toolbar.inspector")
        }
    }
}
