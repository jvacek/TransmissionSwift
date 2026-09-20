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
/// (`/downloads/Movies`) — both for the "On server" preview and for the RPC
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

/// Whether a relative input escapes the default download directory (via `..`)
/// or an absolute input tries to climb above the daemon's root (clamped to
/// `/`). Absolute paths outside the base chosen explicitly (e.g.
/// `/media/torrents`) are intentional, not climbs, so only excess `..` counts
/// for them.
func serverPathClimbsAboveBase(_ input: String, relativeTo base: String?) -> Bool {
    let trimmed = input.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return false }
    if trimmed.hasPrefix("/") {
        var depth = 0
        for component in trimmed.split(separator: "/", omittingEmptySubsequences: false) {
            let part = String(component)
            if part.isEmpty || part == "." { continue }
            if part == ".." {
                if depth == 0 { return true }
                depth -= 1
            } else {
                depth += 1
            }
        }
        return false
    }
    guard let baseTrimmed = base?.trimmingCharacters(in: .whitespaces), !baseTrimmed.isEmpty
    else { return false }
    let baseNorm = baseTrimmed.normalizedDownloadPath
    let resolved = resolveServerPath(trimmed, relativeTo: base)
    if resolved.normalizedDownloadPath == baseNorm { return false }
    return !resolved.hasPrefix(baseNorm + "/")
}

/// Whether a resolved target looks like a folder the daemon hasn't used yet:
/// not the base itself, not root, and not among the known relative folders.
/// The daemon — not this client — decides writability, so callers show this as
/// a neutral hint, never a block.
func serverPathIsNewFolder(resolved: String, relativeTo base: String?, folders: [String]) -> Bool {
    guard !resolved.isEmpty, resolved != "/" else { return false }
    guard let baseTrimmed = base?.trimmingCharacters(in: .whitespaces), !baseTrimmed.isEmpty
    else { return false }
    let baseNorm = baseTrimmed.normalizedDownloadPath
    if resolved.normalizedDownloadPath == baseNorm { return false }
    let relative = relativeDownloadFolder(resolved, relativeTo: base)
    if relative.hasPrefix("/") { return true }
    if relative.isEmpty { return false }
    return !folders.contains(relative)
}

/// Prefill for the Set Location sheet: the single shared folder made relative
/// to the base, or empty when the selection spans several folders (or has no
/// folder) so the field never implies they all live in one place.
func setLocationInitialState(folders: [String], relativeTo base: String?) -> (
    path: String, distinctCount: Int
) {
    let distinct = Set(folders.map { $0.normalizedDownloadPath })
    guard distinct.count == 1, let only = distinct.first else {
        return ("", distinct.count)
    }
    return (initialServerPath(existing: only, relativeTo: base), 1)
}

/// Server-side path input shared by the Set Location and Add Torrent sheets.
///
/// Owns the whole path story so both sheets behave identically: a text field,
/// a visible caption naming the daemon-side contract, the resolved target
/// underneath, and a known-folders menu. The caller binds a raw string and, on
/// submit, passes it through `resolveServerPath(_:relativeTo:)`.
struct ServerPathField: View {
    @Binding var path: String
    let defaultDirectory: String?
    let folders: [String]
    var serverName: String? = nil
    var placeholder: String = "ISOs or /media/torrents"
    var isDisabled: Bool = false

    /// Whether the static path explainer is expanded. Persisted so experienced
    /// users can collapse it once and stop seeing it; the resolved preview and
    /// all warnings stay visible regardless.
    @AppStorage("serverPathHelpExpanded") private var helpExpanded = true

    private var trimmedInput: String {
        path.trimmingCharacters(in: .whitespaces)
    }

    private var isEmptyInput: Bool { trimmedInput.isEmpty }

    private var baseKnown: Bool {
        guard let base = defaultDirectory?.trimmingCharacters(in: .whitespaces) else {
            return false
        }
        return !base.isEmpty
    }

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

    private var contractLines: [String] {
        let base = defaultDirectory?.trimmingCharacters(in: .whitespaces)
        if baseKnown, let base, !base.isEmpty {
            return [
                "Paths are on \(serverScope)'s disk, not on this Mac.",
                "Names without a leading / go under \(base).",
                "A leading / starts from the server's root.",
            ]
        }
        return [
            "Paths are on \(serverScope)'s disk, not on this Mac.",
            "The default folder is unknown — use an absolute path.",
        ]
    }

    private var serverScope: String {
        if let serverName, !serverName.isEmpty { return serverName }
        return "the server"
    }

    private var climbsAboveBase: Bool {
        serverPathClimbsAboveBase(path, relativeTo: defaultDirectory)
    }

    private var isRootTarget: Bool { resolvedPath == "/" }

    private var isNewFolder: Bool {
        !isEmptyInput && !climbsAboveBase && !isRootTarget
            && serverPathIsNewFolder(
                resolved: resolvedPath, relativeTo: defaultDirectory, folders: folders)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            field
            DisclosureGroup(isExpanded: $helpExpanded) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(contractLines, id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if baseKnown {
                        Text("Leave it empty to use the default folder itself.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("The folder must already exist and be writable by the daemon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Preview: \(wrappedPathDisplay)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } label: {
                Button {
                    withAnimation { helpExpanded.toggle() }
                } label: {
                    Text("Learn more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(helpExpanded ? "Hide path help" : "Learn more about paths")
            }
            if climbsAboveBase {
                Text("⚠ “..” climbs above the default folder — clamped to \(wrappedPathDisplay)")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if isRootTarget {
                Text("⚠ The filesystem root is an unusual location.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if isNewFolder {
                Text("New folder — it must exist and be writable by the daemon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The input box, with the known-folders menu docked inside its trailing edge
    /// so it reads as part of the field.
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

    /// Labeled menu (not an icon alone) so the one-click jump to a folder the
    /// daemon already uses is discoverable. Picking a folder is an action that
    /// sets `path`, not a bound selection, so a `Menu` models it more honestly
    /// than a `Picker`.
    private var knownFoldersMenu: some View {
        Menu {
            ForEach(folders, id: \.self) { folder in
                Button(folder) { path = folder }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "folder")
                Text("Known folders")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(isDisabled)
        .help("Jump to a folder the daemon already uses")
        .accessibilityLabel("Known folders")
    }
}

#Preview("Server Path Field") {
    @Previewable @State var path = "Movies"
    return ServerPathField(
        path: $path,
        defaultDirectory: "/downloads",
        folders: ["Linux ISOs", "Creative", "Movies/Marvel"],
        serverName: "Home NAS"
    )
    .padding(20)
    .frame(width: 460)
}
