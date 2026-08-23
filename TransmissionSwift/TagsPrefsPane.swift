import SwiftUI
import TransmissionCore

/// Finder-style tag colour management. Lists every tag in use on the daemon
/// plus any tag that already has a colour assigned (so colours can be cleared
/// even after the last torrent using a tag disappears). Each row's swatch opens
/// the same 7-colour picker the sidebar context menu uses.
struct TagsPrefsPane: View {
    @Environment(TagColorStore.self) private var tagColors
    @Environment(TorrentStore.self) private var store

    private var tags: [String] {
        var names = Set(store.facets.labels.map(\.name))
        names.formUnion(tagColors.coloredLabels)
        return names.sorted()
    }

    var body: some View {
        if tags.isEmpty {
            ContentUnavailableView(
                "No Tags",
                systemImage: "tag",
                description: Text("Add labels to a torrent to manage their colours here.")
            )
        } else {
            Form {
                Section {
                    ForEach(tags, id: \.self) { name in
                        LabeledContent(name) {
                            TagColorPickerButton(current: tagColors.color(for: name)) { color in
                                tagColors.setColor(color, for: name)
                            }
                        }
                    }
                } header: {
                    Text("Tag Colours")
                }
            }
            .formStyle(.grouped)
        }
    }
}

/// A compact swatch button that opens the colour picker. Shows the current
/// colour as a dot, or a muted placeholder when the tag is uncoloured.
private struct TagColorPickerButton: View {
    let current: TagColor?
    let onPick: (TagColor?) -> Void

    var body: some View {
        Menu {
            TagColorPickerMenu(current: current, onPick: onPick)
        } label: {
            HStack(spacing: 6) {
                TagColorDot(color: current)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Tag colour")
    }
}

#Preview {
    let store = TorrentStore(service: MockTorrentService())
    TagsPrefsPane()
        .environment(TagColorStore())
        .environment(store)
        .frame(width: 480, height: 420)
}
