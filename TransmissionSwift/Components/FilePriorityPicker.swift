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
/// the Add Torrent sheet. The whole chip is baked into one image so the
/// borderless menu adds no visible padding around the glyph and caret.
struct FilePriorityPicker: View {
    @Binding var choice: FilePriorityChoice
    var isEnabled: Bool = true
    /// Folder rows show a shared priority only when every descendant agrees;
    /// otherwise the chip shows a mixed glyph and the menu applies to all.
    var isMixed: Bool = false
    var label: String = "File priority"

    @Environment(\.colorScheme) private var colorScheme

    private struct ChipKey: Hashable {
        let choice: FilePriorityChoice
        let isMixed: Bool
        let colorScheme: ColorScheme
    }

    /// Five chips at most per appearance. The image is otherwise re-rendered on
    /// every body pass of every visible file row.
    @MainActor private static var chipCache: [ChipKey: NSImage] = [:]

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
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 31, height: 18)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.16))
        )
        .allowsHitTesting(isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(label)
        .accessibilityValue(isMixed ? "Mixed" : choice.displayLabel)
    }

    private var chip: NSImage {
        let key = ChipKey(choice: choice, isMixed: isMixed, colorScheme: colorScheme)
        if let cached = Self.chipCache[key] { return cached }
        let renderer = ImageRenderer(
            content:
                HStack(spacing: 3) {
                    Image(systemName: isMixed ? "ellipsis" : choice.systemImage)
                        .font(.callout)
                        .foregroundStyle(isMixed ? Color.secondary : choice.displayColor)
                        .frame(width: 12)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 8)
                }
        )
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = false
        Self.chipCache[key] = image
        return image
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
            VStack(spacing: 6) {
                FilePriorityPicker(
                    choice: .constant(.normal), isMixed: true, label: "Mixed priorities")
                Text("Mixed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

#Preview("Priority chip in row") {
    VStack(spacing: 0) {
        HStack(spacing: 4) {
            Spacer()
            Text("21.8 GB")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            FilePriorityPicker(choice: .constant(.normal))
        }
        .padding(.horizontal, 0)
        .frame(height: 22)
        .background(Color.secondary.opacity(0.06))

        HStack(spacing: 4) {
            Spacer()
            Text("658.8 MB")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            FilePriorityPicker(choice: .constant(.high))
        }
        .padding(.horizontal, 0)
        .frame(height: 22)
    }
    .frame(width: 340)
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}
