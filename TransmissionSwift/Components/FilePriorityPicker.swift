import AppKit
import SwiftUI
import TransmissionCore

/// Per-file choice used by the inspector and the Add Torrent sheet's file rows.
/// Folds "don't download" into the priority popup as Skip, like Transmission's
/// own UI.
enum FilePriorityChoice: CaseIterable, Hashable {
    case high, normal, low, skip

    init(file: TorrentFile) {
        self.init(wanted: file.wanted, priority: file.priority)
    }

    init(wanted: Bool, priority: TorrentPriority) {
        guard wanted else {
            self = .skip
            return
        }
        switch priority {
        case .high: self = .high
        case .normal: self = .normal
        case .low: self = .low
        }
    }

    var priority: TorrentPriority? {
        switch self {
        case .high: return .high
        case .normal: return .normal
        case .low: return .low
        case .skip: return nil
        }
    }

    var displayLabel: String {
        switch self {
        case .high: return "High"
        case .normal: return "Normal"
        case .low: return "Low"
        case .skip: return "Skip"
        }
    }

    /// Mirrors the torrent table's priority glyphs, except normal reads as a
    /// flat "minus" so it isn't mistaken for a radio button in compact rows.
    /// Skip (don't download) gets its own slash.
    var systemImage: String {
        switch self {
        case .high: return "chevron.up"
        case .normal: return "minus"
        case .low: return "chevron.down"
        case .skip: return "slash.circle"
        }
    }

    var displayColor: Color {
        switch self {
        case .high: return .orange
        case .normal: return .gray
        case .low: return .blue
        case .skip: return .red
        }
    }

    /// High > Normal > Low > Skip, for sorting.
    var sortRank: Int {
        switch self {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        case .skip: return 3
        }
    }
}

/// Compact priority chip with a menu, shared by the inspector's file rows and
/// the Add Torrent sheet. The glyph and chevron are baked into one image so the
/// native Menu chrome can't strip or misalign them, and the chip keeps a fixed
/// width whichever priority is shown.
struct FilePriorityPicker: View {
    @Binding var choice: FilePriorityChoice
    var isEnabled: Bool = true
    var label: String = "File priority"

    var body: some View {
        Menu {
            ForEach(FilePriorityChoice.allCases, id: \.self) { choice in
                Button {
                    self.choice = choice
                } label: {
                    Label(choice.displayLabel, systemImage: choice.systemImage)
                }
            }
        } label: {
            Image(nsImage: chip)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .allowsHitTesting(isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(label)
        .frame(width: 32, height: 18)
        .padding(.trailing, 5)
    }

    private var chip: NSImage {
        let renderer = ImageRenderer(
            content:
                HStack(spacing: 4) {
                    Image(systemName: choice.systemImage)
                        .font(.callout)
                        .foregroundStyle(choice.displayColor)
                    ZStack {
                        Circle().fill(Color(nsColor: .tertiarySystemFill))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 14, height: 14)
                }
        )
        renderer.scale = 2
        return renderer.nsImage ?? NSImage()
    }
}

#Preview("File Priority Picker") {
    VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 16) {
            ForEach(FilePriorityChoice.allCases, id: \.self) { choice in
                VStack(spacing: 6) {
                    FilePriorityPicker(choice: .constant(choice))
                    Text(choice.displayLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        VStack(alignment: .leading, spacing: 4) {
            FilePriorityPicker(
                choice: .constant(.normal), isEnabled: false, label: "Disabled priority")
            Text("Disabled")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    .padding(20)
}
