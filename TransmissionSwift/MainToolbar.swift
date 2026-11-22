// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

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
/// Three small `ToolbarContent` groups rather than one body: the macOS 26
/// compiler gives up on a body this size ("extra argument in call" at
/// whichever item it reaches first).
struct MainToolbar: ToolbarContent {
    var body: some ToolbarContent {
        AddToolbarGroup()
        SelectionToolbarGroup()
        ToolbarSpacer(.flexible)
        InspectorToggle()
    }
}

/// Group 1 — Add.
private struct AddToolbarGroup: ToolbarContent {
    @Environment(TorrentStore.self) private var store

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Add", systemImage: "plus") {
                store.openAddSheet()
            }
            .disabled(!store.actionsEnabled)
            .help("Add torrent file")
            .accessibilityIdentifier("toolbar.add")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Add Link", systemImage: "link") {
                store.openAddSheet(mode: .link)
            }
            .disabled(!store.actionsEnabled)
            .help("Add magnet link or URL")
            .accessibilityIdentifier("toolbar.addLink")
        }
    }
}

/// Group 2 — actions on the selected torrents.
private struct SelectionToolbarGroup: ToolbarContent {
    @Environment(TorrentStore.self) private var store

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Resume", systemImage: "play.fill") {
                Task { await store.actions.start(Array(store.list.selectedTorrentIDs)) }
            }
            .disabled(!store.actionsEnabled || !store.list.selectionStartStop.canStart)
            .help("Resume selected torrents")
            .accessibilityIdentifier("toolbar.resume")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Pause", systemImage: "pause.fill") {
                Task { await store.actions.stop(Array(store.list.selectedTorrentIDs)) }
            }
            .disabled(!store.actionsEnabled || !store.list.selectionStartStop.canStop)
            .help("Pause selected torrents")
            .accessibilityIdentifier("toolbar.pause")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Remove", systemImage: "trash", role: .destructive) {
                store.actions.requestRemove(Array(store.list.selectedTorrentIDs))
            }
            .disabled(!store.actionsEnabled || store.list.selectedTorrentIDs.isEmpty)
            .help("Remove selected torrents")
            .accessibilityIdentifier("toolbar.remove")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Set Location", systemImage: "folder") {
                store.openSetLocation(for: Array(store.list.selectedTorrentIDs))
            }
            .disabled(!store.actionsEnabled || store.list.selectedTorrentIDs.isEmpty)
            .help("Set download location for selected torrents")
            .accessibilityIdentifier("toolbar.setLocation")
        }
    }
}

/// The inspector's tab picker in the column's own toolbar section, above the
/// column as in Xcode. Declared on every layout and left empty rather than
/// wrapped in a builder `if`: a conditional in a `ToolbarContentBuilder` body
/// fails the macOS 26 compiler when it reads the environment.
struct InspectorTabsToolbar: ToolbarContent {
    @Environment(TorrentStore.self) private var store
    /// The column's toolbar section only exists when the inspector is open, and
    /// only a window wide enough to hold the picker uses it.
    let shows: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if shows, store.list.selectedTorrents.first != nil {
                InspectorTabPicker()
                    .frame(minWidth: 160, idealWidth: 220, maxWidth: 260)
            }
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

/// Show/Hide Inspector. Its own `ToolbarContent` rather than an inline item:
/// the macOS 26 compiler fails the whole toolbar body when the item sits here.
struct InspectorToggle: ToolbarContent {
    @Environment(TorrentStore.self) private var store

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            // Same wording as the View menu item.
            let title = store.inspector.isVisible ? "Hide Inspector" : "Show Inspector"
            Button(title, systemImage: "sidebar.right") {
                store.inspector.isVisible.toggle()
            }
            .help(title)
            .accessibilityIdentifier("toolbar.inspector")
        }
    }
}
