import SwiftUI
import TransmissionCore

/// Thin tinted progress bar + trailing percentage. Used inside the torrent
/// table's Progress column.
struct ProgressBar: View {
    let value: Double
    let status: TorrentStatus

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
                .tint(status.displayColor)
                .frame(maxWidth: .infinity)
            Text("\(Int(value * 100))%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .transaction { $0.animation = nil }
    }
}

#Preview {
    VStack(alignment: .leading) {
        ProgressBar(value: 0.62, status: .downloading)
        ProgressBar(value: 1.0, status: .seeding)
        ProgressBar(value: 0.34, status: .paused)
        ProgressBar(value: 0.91, status: .checking)
        ProgressBar(value: 0.44, status: .error)
    }
    .frame(width: 240)
    .padding()
}
