// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI

/// Standard bottom row for sheets: an optional leading accessory (a Test
/// button, a status line), then Cancel and the default action, trailing. The
/// default action is tinted by `.defaultAction`, so no explicit button style.
struct SheetButtonRow<Leading: View>: View {
    private let confirmTitle: String
    private let busyTitle: String?
    private let isBusy: Bool
    private let canConfirm: Bool
    private let onCancel: () -> Void
    private let onConfirm: () -> Void
    private let leading: Leading

    init(
        _ confirmTitle: String,
        busyTitle: String? = nil,
        isBusy: Bool = false,
        canConfirm: Bool = true,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void,
        @ViewBuilder leading: () -> Leading
    ) {
        self.confirmTitle = confirmTitle
        self.busyTitle = busyTitle
        self.isBusy = isBusy
        self.canConfirm = canConfirm
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self.leading = leading()
    }

    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer(minLength: 8)
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .disabled(isBusy)
            Button(isBusy ? (busyTitle ?? confirmTitle) : confirmTitle, action: onConfirm)
                .keyboardShortcut(.defaultAction)
                .disabled(isBusy || !canConfirm)
        }
    }
}

extension SheetButtonRow where Leading == EmptyView {
    init(
        _ confirmTitle: String,
        busyTitle: String? = nil,
        isBusy: Bool = false,
        canConfirm: Bool = true,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.init(
            confirmTitle, busyTitle: busyTitle, isBusy: isBusy, canConfirm: canConfirm,
            onCancel: onCancel, onConfirm: onConfirm, leading: { EmptyView() })
    }
}
