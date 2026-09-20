import SwiftUI

/// Known-folder suggestions for a server-side destination path. `known` is the
/// torrent folder rollup from `FilterFacets` — relative folder names, where the
/// empty string is the sentinel for torrents sitting directly in the default
/// download directory. That sentinel names the default folder itself, not a
/// destination worth jumping to, so it is dropped. The result is deliberately
/// independent of any typed path: every known folder stays one click away.
func knownFolderSuggestions(_ known: [String]) -> [String] {
    known.filter { !$0.isEmpty }
}

/// The "Known folders" block shared by the Set Location and Add Torrent sheets:
/// a caption plus a scrollable list of tappable folder pills. Renders nothing
/// when there are no known folders.
struct KnownFoldersList: View {
    let folders: [String]
    let onSelect: (String) -> Void

    var body: some View {
        if !folders.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Known folders")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(folders, id: \.self) { folder in
                            KnownFolderButton(folder: folder) { onSelect(folder) }
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
    }
}

/// One row in the "Known folders" list. A bordered, hover-highlighted pill so
/// it reads as a tappable destination rather than a line of text.
private struct KnownFolderButton: View {
    let folder: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(folder)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .opacity(isHovering ? 1 : 0.4)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHovering ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.secondary.opacity(isHovering ? 0.35 : 0.15))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Use \(folder)")
    }
}

/// Compact disclosure control that expands the known-folders list. Deliberately
/// a plain custom capsule rather than `.glass`, whose button chrome is too tall
/// to sit comfortably next to the destination field.
struct KnownFoldersToggle: View {
    @Binding var isExpanded: Bool

    @State private var isHovering = false

    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.2)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                isHovering ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(Color.secondary.opacity(isHovering ? 0.35 : 0.15))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isExpanded ? "Hide known folders" : "Show known folders")
        .accessibilityLabel("Known folders")
    }
}

#Preview("Known Folders") {
    KnownFoldersList(
        folders: [
            "Linux ISOs",
            "Creative",
            "Movies/Marvel",
            "A very long folder name that should truncate nicely",
        ],
        onSelect: { _ in }
    )
    .padding(20)
    .frame(width: 380)
}

#Preview("Known Folders Toggle") {
    HStack(spacing: 16) {
        KnownFoldersToggle(isExpanded: .constant(false))
        KnownFoldersToggle(isExpanded: .constant(true))
    }
    .padding(40)
    .frame(width: 260)
}
