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
                            TagColorRadioPicker(current: tagColors.color(for: name)) { color in
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

/// A horizontal radio row of the seven tag colours. The active colour shows a
/// tick; a trailing "no colour" dot (slashed circle) clears the assignment.
private struct TagColorRadioPicker: View {
    let current: TagColor?
    let onPick: (TagColor?) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(TagColor.allCases, id: \.self) { color in
                Button {
                    onPick(color)
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 18, height: 18)
                        .overlay {
                            if current == color {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(color == .yellow ? Color.black : Color.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.displayName)
            }

            Button {
                onPick(nil)
            } label: {
                Circle()
                    .stroke(Color.secondary, lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                    .overlay {
                        if current == nil {
                            Image(systemName: "slash")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("No colour")
        }
    }
}

#Preview {
    let store = TorrentStore(service: MockTorrentService())
    TagsPrefsPane()
        .environment(TagColorStore())
        .environment(store)
        .frame(width: 480, height: 420)
}
