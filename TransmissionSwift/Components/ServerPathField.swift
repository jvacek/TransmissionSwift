import SwiftUI

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

/// Server-side path input shared by the Set Location and Add Torrent sheets.
///
/// Owns the whole path story so both sheets behave identically: a text field
/// that accepts a path relative to the daemon's default download directory (or
/// absolute when it starts with `/`), a one-line explanation, the resolved
/// "Full path", and a known-folders menu docked in the field. The caller binds
/// a raw string and, on submit, passes it through
/// `resolveServerPath(_:relativeTo:)`.
struct ServerPathField: View {
    @Binding var path: String
    let defaultDirectory: String?
    let folders: [String]
    var placeholder: String = "Location on the server"
    var isDisabled: Bool = false
    /// Optional format/validation hook, e.g. a monospaced destination style.
    var configureField: (TextField<Text>) -> AnyView = { AnyView($0.textFieldStyle(.plain)) }

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
            Text(explanation)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
    /// so it reads as part of the field.
    private var field: some View {
        HStack(spacing: 6) {
            configureField(TextField(placeholder, text: $path))
                .disabled(isDisabled)
            if !folders.isEmpty {
                knownFoldersMenu
            }
        }
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

    private var explanation: String {
        "Paths are relative to the default download dir. Start with “/” for an absolute path."
    }
}

#Preview("Server Path Field") {
    @Previewable @State var path = "Movies"
    return ServerPathField(
        path: $path,
        defaultDirectory: "/downloads",
        folders: ["Linux ISOs", "Creative", "Movies/Marvel"],
        placeholder: "Location on the server"
    )
    .padding(20)
    .frame(width: 460)
}
