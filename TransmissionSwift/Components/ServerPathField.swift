import SwiftUI
import TransmissionCore

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

// MARK: - Shared destination logic

/// The Set Location and Add Torrent sheets share one path contract — empty
/// means the default download dir, anything else is relative to it (or absolute
/// from `/`) — so the helpers below live here next to `resolveServerPath`
/// instead of drifting apart per sheet.

/// Display string for a destination field: `existing` made relative to `base`
/// when nested inside it, `""` when it *is* the base (empty resolves back to
/// the base on submit) or when there is no existing path (new torrent).
/// Anything outside the base stays absolute. Trailing slashes are normalized
/// by `relativeDownloadFolder`.
func initialServerPath(existing: String?, relativeTo base: String?) -> String {
    guard let existing else { return "" }
    return relativeDownloadFolder(
        existing.trimmingCharacters(in: .whitespaces),
        relativeTo: base?.trimmingCharacters(in: .whitespaces))
}

/// Whether a destination field value is submittable: anything non-empty always
/// is; empty resolves to the base, so it needs a known base.
func isSubmittableServerPath(_ input: String, relativeTo base: String?) -> Bool {
    guard input.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
    guard let base = base?.trimmingCharacters(in: .whitespaces) else { return false }
    return !base.isEmpty
}

/// Known-folder suggestions from the sidebar facet rollup, dropping the
/// default-folder sentinel. Takes the facets directly so both sheets share the
/// mapping instead of each repeating it.
func serverPathSuggestions(from facets: FilterFacets) -> [String] {
    knownFolderSuggestions(facets.folders.map(\.name))
}

/// Server-side path input shared by the Set Location and Add Torrent sheets.
///
/// Owns the whole path story so both sheets behave identically: a text field
/// whose placeholder teaches the relative format by example, the resolved
/// "Full path" underneath, and a known-folders menu docked in the field. The
/// caller binds a raw string and, on submit, passes it through
/// `resolveServerPath(_:relativeTo:)`. The relative-vs-absolute rule lives in
/// the field's tooltip rather than a visible line — the Full-path preview
/// already shows where the input lands.
struct ServerPathField: View {
    @Binding var path: String
    let defaultDirectory: String?
    let folders: [String]
    var placeholder: String = "relative/to/default-download-dir"
    var isDisabled: Bool = false

    private var resolvedPath: String {
        resolveServerPath(path, relativeTo: defaultDirectory)
    }

    /// The resolved path as a directory (always a trailing slash), so it's clear
    /// the location is the folder the torrent's files land in.
    private var resolvedPathDisplay: String {
        var display = resolvedPath
        if !display.hasSuffix("/") { display += "/" }
        return display
    }

    /// Zero-width spaces after each slash let a long path wrap at directory
    /// boundaries instead of ellipsing.
    private var wrappedPathDisplay: String {
        resolvedPathDisplay.replacingOccurrences(of: "/", with: "/\u{200B}")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            field
            Text("Full path: \(wrappedPathDisplay)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The input box, with the known-folders menu docked inside its trailing edge
    /// so it reads as part of the field. The relative-vs-absolute rule lives in
    /// the tooltip — the Full-path preview below already shows where the input
    /// lands, so a visible explanation line would just repeat it.
    private var field: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $path)
                .textFieldStyle(.plain)
                .monospaced()
                .disabled(isDisabled)
            if !folders.isEmpty {
                knownFoldersMenu
            }
        }
        .help("Paths are relative to the default download dir. Start with “/” for an absolute path.")
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.secondary.opacity(0.25))
        )
    }

    /// Native menu: the system owns anchoring, dismissal, keyboard traversal, and
    /// scrolling. Picking a folder is an action that sets `path`, not a bound
    /// selection, so a `Menu` models it more honestly than a `Picker`.
    private var knownFoldersMenu: some View {
        Menu {
            ForEach(folders, id: \.self) { folder in
                Button(folder) { path = folder }
            }
        } label: {
            Image(systemName: "folder")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(isDisabled)
        .help("Use a known folder")
        .accessibilityLabel("Known folders")
    }
}

#Preview("Server Path Field") {
    @Previewable @State var path = "Movies"
    return ServerPathField(
        path: $path,
        defaultDirectory: "/downloads",
        folders: ["Linux ISOs", "Creative", "Movies/Marvel"]
    )
    .padding(20)
    .frame(width: 460)
}
