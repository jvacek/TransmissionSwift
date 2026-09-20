import SwiftUI
import TransmissionCore

/// Sheet for relocating one or more torrents on the daemon host.
///
/// The text field takes a path on the *daemon's* filesystem. Paths starting
/// with `/` are absolute (from the daemon's root); anything else is relative to
/// the daemon's default download directory (`store.downloadDirectory`). `..`
/// and `.` are resolved lexically so the preview always shows the real target.
/// `move` mirrors RPC `torrent-set-location`'s flag: true relocates the existing
/// data, false only repoints the torrent when the data was moved out-of-band.
struct SetLocationSheet: View {
    @Environment(TorrentStore.self) private var store
    @Binding var isPresented: Bool
    let ids: [Torrent.ID]

    @State private var location: String = ""
    @State private var moveData = true
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set Location")
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                TextField("Location on the server", text: $location)
                    .disabled(isSaving)
                Text(pathExplanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Full path: \(resolvedPathDisplay)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Known folders")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(suggestions, id: \.self) { folder in
                                KnownFolderButton(folder: folder) { location = folder }
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
            }

            Toggle("Move data to the new location", isOn: $moveData)
                .disabled(isSaving)
                .help(
                    "On: Transmission moves the existing files. Off: only update the path (use when you moved the data yourself)."
                )

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button(isSaving ? "Applying…" : "Apply") {
                    Task { await apply() }
                }
                .buttonStyle(.glassProminent)
                .disabled(isSaving || location.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { location = initialLocation }
    }

    private var initialLocation: String {
        let selected = store.torrents.filter { ids.contains($0.id) }
        if let first = selected.first {
            return first.downloadFolder
        }
        return store.downloadDirectory ?? ""
    }

    private var subtitle: String {
        ids.count == 1 ? "1 torrent selected" : "\(ids.count) torrents selected"
    }

    private var resolvedPath: String {
        resolveServerPath(location, relativeTo: store.downloadDirectory)
    }

    /// The full path shown under the field, with a zero-width space after every
    /// slash so a long path wraps at directory boundaries instead of ellipsing.
    private var resolvedPathDisplay: String {
        resolvedPath.replacingOccurrences(of: "/", with: "/\u{200B}")
    }

    private var pathExplanation: String {
        if let base = store.downloadDirectory, !base.isEmpty {
            return
                "A path starting with “/” is absolute on the server. Anything else is relative to the server's default download folder (\(base))."
        }
        return
            "A path starting with “/” is absolute on the server. Anything else is relative to the server's default download folder."
    }

    private var suggestions: [String] {
        knownFolderSuggestions(store.facets.folders.map(\.name))
    }

    private func apply() async {
        isSaving = true
        defer { isSaving = false }
        let trimmed = location.trimmingCharacters(in: .whitespaces)
        let resolved = resolveServerPath(trimmed, relativeTo: store.downloadDirectory)
        await store.setLocation(ids, location: resolved, move: moveData)
        isPresented = false
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

/// Resolve a torrent location path as the daemon would:
/// - leading `/`  -> absolute from the daemon's root;
/// - otherwise    -> joined onto `base` (the daemon's default download dir);
/// `.` and `..` are resolved lexically without touching the filesystem. `/`
/// paths can't climb above root; relative paths can't climb above `base`.
///
/// The result keeps a leading `/` whenever either the input or `base` is rooted,
/// so a relative entry like `Movies` still yields a real full path
/// (`/downloads/Movies`) — both for the "Full path" preview and for the RPC
/// call, which needs an absolute path on the daemon.
func resolveServerPath(_ input: String, relativeTo base: String?) -> String {
    let trimmed = input.trimmingCharacters(in: .whitespaces)
    let baseTrimmed = (base ?? "").trimmingCharacters(in: .whitespaces)
    let absoluteInput = trimmed.hasPrefix("/")
    let absoluteBase = baseTrimmed.hasPrefix("/")

    let working: String
    if absoluteInput {
        working = trimmed
    } else if baseTrimmed.isEmpty {
        working = trimmed.isEmpty ? "/" : trimmed
    } else {
        working = trimmed.isEmpty ? baseTrimmed : baseTrimmed + "/" + trimmed
    }

    var out: [String] = []
    for component in working.split(separator: "/", omittingEmptySubsequences: false) {
        let part = String(component)
        if part.isEmpty { continue }
        if part == "." { continue }
        if part == ".." {
            if !out.isEmpty {
                out.removeLast()
            }
            continue
        }
        out.append(part)
    }

    let isRooted = absoluteInput || absoluteBase
    let result = (isRooted ? "/" : "") + out.joined(separator: "/")
    guard result != "/", !result.isEmpty else { return isRooted ? "/" : "" }
    return result
}

/// Known-folder buttons for the Set Location field. `known` is the torrent
/// folder rollup from `FilterFacets`. The default-download-dir sentinel (`""`)
/// names the default folder itself, not a destination worth jumping to, so it is
/// dropped. The result is deliberately independent of the typed path — every
/// known folder stays one click away rather than being filtered as you type.
func knownFolderSuggestions(_ known: [String]) -> [String] {
    known.filter { !$0.isEmpty }
}

#Preview("Set Location") {
    let store = TorrentStore(service: MockTorrentService())
    return SetLocationSheet(isPresented: .constant(true), ids: [2])
        .environment(store)
        .environment(TagColorStore())
        .frame(width: 460)
}
