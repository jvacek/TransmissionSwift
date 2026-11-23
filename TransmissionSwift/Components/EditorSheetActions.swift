// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

/// Duplicate and Remove for an editor sheet's `SheetButtonRow`, shown only for
/// a saved item. Remove asks first; Duplicate waits until edits are saved or
/// cancelled, so the copy matches what's on disk.
struct EditorSheetActions: View {
    let isDirty: Bool
    let duplicateHelp: String
    let removalTitle: String
    let removalMessage: String
    let onDuplicate: (() -> Void)?
    let onRemove: (() -> Void)?

    @State private var confirmingRemoval = false

    var body: some View {
        if let onDuplicate {
            Button("Duplicate", action: onDuplicate)
                .disabled(isDirty)
                .help(isDirty ? "Save or cancel your changes first" : duplicateHelp)
        }
        if let onRemove {
            Button("Remove…", role: .destructive) { confirmingRemoval = true }
                .confirmationDialog(removalTitle, isPresented: $confirmingRemoval) {
                    Button("Remove", role: .destructive, action: onRemove)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(removalMessage)
                }
        }
    }
}

extension View {
    /// Asks before removing the item a list row's context menu staged in `item`.
    func removalConfirmation<Item>(
        _ title: String,
        item: Binding<Item?>,
        message: @escaping (Item) -> String,
        onRemove: @escaping (Item) -> Void
    ) -> some View {
        confirmationDialog(
            title,
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            presenting: item.wrappedValue
        ) { value in
            Button("Remove", role: .destructive) { onRemove(value) }
            Button("Cancel", role: .cancel) {}
        } message: { value in
            Text(message(value))
        }
    }
}
