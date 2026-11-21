// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import TransmissionCore

/// Thin tinted progress bar + trailing percentage. Used inside the torrent
/// table's Progress column.
struct ProgressBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        // `.transaction { $0.animation = nil }` wipes any inherited animation
        // context. `ProgressView` (which is NSProgressIndicator on macOS)
        // lerps its `value` implicitly — without this, table-cell reuse on
        // sidebar filter changes makes the bar slide between the old row's
        // value and the new one's. Row insert/delete animations on the Table
        // itself are left to do their thing.
        HStack(spacing: 6) {
            ProgressView(value: max(0, min(1, value)))
                .progressViewStyle(.linear)
                .tint(tint)
                .frame(maxWidth: .infinity)
            Text("\(Int(value * 100))%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .transaction { $0.animation = nil }
    }
}

#if DEBUG
#Preview {
    VStack(alignment: .leading) {
        ProgressBar(value: 0.62, tint: TorrentStatus.downloading.displayColor)
        ProgressBar(value: 1.0, tint: TorrentStatus.seeding.displayColor)
        ProgressBar(value: 0.34, tint: TorrentStatus.paused.displayColor)
        ProgressBar(value: 0.91, tint: TorrentStatus.checking.displayColor)
        ProgressBar(value: 0.44, tint: TorrentStatus.error.displayColor)
    }
    .frame(width: 240)
    .padding()
}
#endif
