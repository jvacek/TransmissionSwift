// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import SwiftUI
import TransmissionCore

/// One row of the Add Torrent sheet's file tree. Folders carry every descendant
/// file index, so folder actions apply to the whole subtree.
nonisolated struct AddTorrentFileNode: Identifiable, Equatable {
    enum Kind: Equatable {
        case folder
        case file(Int)
    }

    let id: String
    let name: String
    let kind: Kind
    let children: [AddTorrentFileNode]?
    let fileIndices: [Int]

    var isFolder: Bool {
        if case .folder = kind { return true }
        return false
    }

    var nodeCount: Int {
        1 + (children?.reduce(0) { $0 + $1.nodeCount } ?? 0)
    }

    /// This node and every descendant, for pruning selection on collapse.
    var nodeIDs: [String] {
        [id] + (children?.flatMap(\.nodeIDs) ?? [])
    }

    /// Every folder ID in this subtree, used to start fully expanded.
    var folderIDs: [String] {
        (isFolder ? [id] : []) + (children?.flatMap(\.folderIDs) ?? [])
    }

    static func tree(from files: [TorrentAddFile]) -> [AddTorrentFileNode] {
        build(
            entries: files.map { (index: $0.index, components: $0.path) },
            parentPath: [])
    }

    private static func build(
        entries: [(index: Int, components: [String])],
        parentPath: [String]
    ) -> [AddTorrentFileNode] {
        let groups = Dictionary(grouping: entries) { $0.components.first ?? "" }
        var nodes: [AddTorrentFileNode] = []
        for (name, group) in groups {
            let folderEntries = group.filter { $0.components.count > 1 }
            if !folderEntries.isEmpty {
                let path = parentPath + [name]
                let children = build(
                    entries: folderEntries.map {
                        ($0.index, Array($0.components.dropFirst()))
                    },
                    parentPath: path)
                nodes.append(
                    AddTorrentFileNode(
                        id: "folder:" + path.map(Self.idFragment).joined(separator: "/"),
                        name: name,
                        kind: .folder,
                        children: children.isEmpty ? nil : children,
                        fileIndices: children.flatMap(\.fileIndices).sorted()))
            }
            for entry in group where entry.components.count == 1 {
                nodes.append(
                    AddTorrentFileNode(
                        id: "file:\(entry.index)",
                        name: name,
                        kind: .file(entry.index),
                        children: nil,
                        fileIndices: [entry.index]))
            }
        }
        return nodes.sorted { lhs, rhs in
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// A path component can legally contain anything bencode allows, so keep
    /// the readable separators in normal paths but never let a component's `/`
    /// turn a nested folder and a flat one into the same identity.
    private static func idFragment(_ component: String) -> String {
        component.replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "/", with: "%2F")
    }
}

/// One rendered row of the flattened tree.
struct VisibleFileRow: Identifiable {
    let node: AddTorrentFileNode
    let depth: Int

    var id: String { node.id }
}

/// Row height the native List lays out, and the content height inside it. The
/// outer value is used to size the fixed-height list; the inner one plus the
/// row insets makes each row the same height as the old custom list.
let addFileRowHeight: CGFloat = 26
let addFileContentHeight: CGFloat = 22

struct AddTorrentFileRow: View {
    @Binding var file: TorrentAddFile
    let name: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Color.clear
                .frame(width: 12, height: 18)

            NativeCheckbox(
                state: file.wanted ? true : false,
                allowsMixedState: false,
                label: "Download \(file.pathString)",
                action: { file.wanted.toggle() }
            )
            .frame(width: 18, height: 18)

            Image(systemName: "doc")
                .font(.callout)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .frame(width: 16)

            Text(name)
                .font(.callout.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(fileTextColor)

            Spacer(minLength: 8)

            Text(ColumnFormatters.humanizedSize(file.length))
                .font(.caption.monospacedDigit())
                .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)

            FilePriorityPicker(
                choice: Binding(
                    get: { FilePriorityChoice(wanted: file.wanted, priority: file.priority) },
                    set: { choice in
                        if let priority = choice.priority {
                            file.wanted = true
                            file.priority = priority
                        } else {
                            file.wanted = false
                        }
                    }),
                label: "Priority for \(file.pathString)"
            )
        }
        .padding(.horizontal, 0)
        .frame(height: addFileContentHeight)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fileTextColor: Color {
        if isSelected { return .white }
        return file.wanted ? .primary : .secondary
    }
}

struct AddTorrentFolderRow: View {
    let name: String
    let size: Int64
    let allWanted: Bool
    let anyWanted: Bool
    let choice: FilePriorityChoice?
    let isExpanded: Bool
    let isSelected: Bool
    let onToggleExpansion: () -> Void
    let onToggle: () -> Void
    let onPriority: (FilePriorityChoice) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onToggleExpansion) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 12, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isExpanded ? "Collapse folder \(name)" : "Expand folder \(name)")

            NativeCheckbox(
                state: allWanted ? true : (anyWanted ? nil : false),
                allowsMixedState: true,
                label: "Download folder \(name)",
                action: onToggle
            )
            .frame(width: 18, height: 18)

            Image(systemName: "folder.fill")
                .font(.callout)
                .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                .frame(width: 16)

            Text(name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? Color.white : Color.primary)

            Spacer(minLength: 8)

            Text(ColumnFormatters.humanizedSize(size))
                .font(.caption.monospacedDigit())
                .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)

            FilePriorityPicker(
                choice: Binding(
                    get: { choice ?? .normal },
                    set: { onPriority($0) }),
                isMixed: choice == nil,
                label: "Priority for folder \(name)")
        }
        .padding(.horizontal, 0)
        .frame(height: addFileContentHeight)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// AppKit's own checkbox, used for both files and folders so they render
/// identically. Folders opt into AppKit's mixed state; files are plain on/off.
private struct NativeCheckbox: NSViewRepresentable {
    let state: Bool?
    let allowsMixedState: Bool
    let label: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            checkboxWithTitle: "",
            target: context.coordinator,
            action: #selector(Coordinator.clicked))
        button.setButtonType(.switch)
        button.allowsMixedState = allowsMixedState
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.allowsMixedState = allowsMixedState
        button.state =
            allowsMixedState && state == nil ? .mixed : (state == true ? .on : .off)
        button.setAccessibilityLabel(label)
        button.setAccessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard allowsMixedState else { return state == true ? "On" : "Off" }
        if state == true { return "All files" }
        if state == nil { return "Some files" }
        return "No files"
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func clicked() {
            action()
        }
    }
}

#Preview("File rows") {
    VStack(spacing: 0) {
        AddTorrentFolderRow(
            name: "Season 01", size: 4_455_000_000,
            allWanted: true, anyWanted: true, choice: .normal,
            isExpanded: true, isSelected: false,
            onToggleExpansion: {}, onToggle: {}, onPriority: { _ in })
        AddTorrentFolderRow(
            name: "Subs", size: 100_000,
            allWanted: false, anyWanted: true, choice: nil,
            isExpanded: true, isSelected: true,
            onToggleExpansion: {}, onToggle: {}, onPriority: { _ in }
        )
        .background(Color(nsColor: .selectedContentBackgroundColor))
        AddTorrentFileRow(
            file: .constant(
                TorrentAddFile(
                    index: 0, path: ["Season 01", "Episode 01.mkv"], length: 1_482_000_000)),
            name: "Episode 01.mkv", isSelected: false)
        AddTorrentFileRow(
            file: .constant(
                TorrentAddFile(
                    index: 1, path: ["Season 01", "Episode 02.mkv"], length: 1_510_000_000,
                    wanted: false)),
            name: "Episode 02.mkv", isSelected: false)
        AddTorrentFileRow(
            file: .constant(
                TorrentAddFile(
                    index: 2, path: ["Season 01", "Episode 03.mkv"], length: 1_463_000_000,
                    priority: .high)),
            name: "Episode 03.mkv", isSelected: true
        )
        .background(Color(nsColor: .selectedContentBackgroundColor))
        AddTorrentFileRow(
            file: .constant(
                TorrentAddFile(
                    index: 3, path: ["Season 01", "Episode 04.mkv"], length: 1_501_000_000,
                    wanted: false)),
            name: "Episode 04.mkv", isSelected: true
        )
        .background(Color(nsColor: .selectedContentBackgroundColor))
    }
    .frame(width: 520)
    .padding()
    .background(Color(nsColor: .windowBackgroundColor))
}
