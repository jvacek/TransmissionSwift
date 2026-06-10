import SwiftUI
import TransmissionCore

/// Small coloured dot that fronts every torrent row. Status is exposed to
/// VoiceOver via the accessibility label — colour alone never carries meaning.
struct StatusDot: View {
    let status: TorrentStatus
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(status.displayColor)
            .frame(width: size, height: size)
            .accessibilityLabel(status.displayLabel)
    }
}

#Preview {
    HStack(spacing: 12) {
        ForEach(TorrentStatus.allCases, id: \.self) { status in
            VStack {
                StatusDot(status: status)
                Text(status.displayLabel).font(.caption2)
            }
        }
    }
    .padding()
}
