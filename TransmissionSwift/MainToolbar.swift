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
struct MainToolbar: ToolbarContent {
    @Environment(TorrentStore.self) private var store
    /// Whether the inspector owns the toggle in its own toolbar section.
    let inspectorInToolbar: Bool

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
            Button("Add Link", systemImage: "link") {
                store.openAddSheet(mode: .link)
            }
            .disabled(!store.actionsEnabled)
            .help("Add magnet link or URL")
            .accessibilityIdentifier("toolbar.addLink")
        }

        // Search sits between the add buttons and the selection actions.
        ToolbarSpacer(.fixed)
        SearchToolbarItem()

        ToolbarSpacer(.fixed)

        // Group 2 — selection actions
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

        ToolbarSpacer(.flexible)

        // Group 3 — view toggles. While the inspector is open and the window is
        // wide, the inspector column declares the toggle instead (see
        // `MainWindow`), so it sits in the toolbar section above it, as in Xcode.
        if !inspectorInToolbar || !store.inspector.isVisible {
            ToolbarSpacer(.fixed)
            InspectorToggle()
        }
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

/// The search control, in its own `ToolbarContent` for the same type-check
/// reason as `InspectorToggle`.
struct SearchToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) { ToolbarSearchField() }
    }
}

/// Finder-style search: a magnifier button that opens into a search field on
/// click or ⌘F, and closes again once editing ends with nothing typed.
///
/// Hand-rolled because `.searchable` always lands in the trailing toolbar
/// section, which is above the inspector while it's open.
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

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            // Escape clears the search and gives focus back to the window.
            parent.text = ""
            control.stringValue = ""
            control.window?.makeFirstResponder(nil)
            return true
        }
    }
}
