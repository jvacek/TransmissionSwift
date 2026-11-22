// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
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
/// Small `ToolbarContent` groups rather than one body: the macOS 26 compiler
/// gives up on a body this size ("extra argument in call" at whichever item
/// it reaches first).
struct MainToolbar: ToolbarContent {
    @Environment(TorrentStore.self) private var store

    var body: some ToolbarContent {
        AddToolbarGroup()
        ToolbarSpacer(.fixed)
        SelectionToolbarGroup()
        ToolbarSpacer(.flexible)
        SearchToolbarItem()
        ToolbarSpacer(.fixed)
        InspectorToggle(shows: !store.inspector.isVisible)
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

/// Show/Hide Inspector. The list toolbar declares it while the inspector is
/// closed and the inspector column while it's open, so it sits above the
/// column as in Xcode. Both are declared on every layout and left empty when
/// they don't apply: a builder `if` that reads the environment fails the
/// macOS 26 compiler, and SwiftUI keeps a hidden inspector's items around.
struct InspectorToggle: ToolbarContent {
    @Environment(TorrentStore.self) private var store
    let shows: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if shows {
                // Same wording as the View menu item.
                let title = store.inspector.isVisible ? "Hide Inspector" : "Show Inspector"
                Button(title, systemImage: "sidebar.right") {
                    store.inspector.isVisible.toggle()
                }
                .help(title)
                .accessibilityIdentifier("toolbar.inspector")
            }
        }
        .sharedBackgroundVisibility(shows ? .automatic : .hidden)
    }
}

/// Search, in its own `ToolbarContent` for the same type-check reason as
/// `InspectorToggle`.
private struct SearchToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) { ToolbarSearchField() }
    }
}

/// Finder-style search: a magnifier button that opens into a search field on
/// click or ⌘F, and closes again once editing ends with nothing typed.
///
/// Hand-rolled because `.searchable` always lands in the trailing toolbar
/// section, which is above the inspector while it's open, and macOS has no
/// collapsed search behaviour (`searchToolbarBehavior(.minimize)` is iOS-only).
private struct ToolbarSearchField: View {
    @Environment(TorrentStore.self) private var store
    @State private var expanded = false
    @State private var focusRequest = 0

    var body: some View {
        @Bindable var list = store.list
        Group {
            if expanded || !list.searchQuery.isEmpty {
                SearchFieldView(text: $list.searchQuery, focusRequest: focusRequest) {
                    if list.searchQuery.isEmpty { close() }
                }
                .frame(width: 220)
            } else {
                Button("Search", systemImage: "magnifyingglass") { open() }
                    .help("Search torrents")
                    .accessibilityIdentifier("toolbar.searchButton")
            }
        }
        .onChange(of: store.ui.searchFocusRequest) { open() }
    }

    private func open() {
        focusRequest += 1
        withAnimation(.smooth(duration: 0.2)) { expanded = true }
    }

    private func close() {
        withAnimation(.smooth(duration: 0.2)) { expanded = false }
    }
}

/// `NSSearchField`, because `@FocusState` doesn't reach into toolbar items:
/// focus goes through the window's first responder instead.
private struct SearchFieldView: NSViewRepresentable {
    @Binding var text: String
    /// Each change focuses the field.
    let focusRequest: Int
    let onEndEditing: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search torrents"
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier("toolbar.search")
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.handledFocusRequest != focusRequest {
            context.coordinator.handledFocusRequest = focusRequest
            // Deferred: a freshly inserted field has no window yet.
            Task { @MainActor in field.window?.makeFirstResponder(field) }
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchFieldView
        var handledFocusRequest: Int?

        init(_ parent: SearchFieldView) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onEndEditing()
        }

        func control(
            _ control: NSControl, textView: NSTextView, doCommandBy selector: Selector
        ) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            // Escape clears the search and gives focus back to the window.
            parent.text = ""
            control.stringValue = ""
            control.window?.makeFirstResponder(nil)
            return true
        }
    }
}
