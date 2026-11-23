// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import TransmissionCore

/// The Add Torrent sheet's file selection: a filterable tree of the
/// `.torrent`'s files with per-file and bulk wanted/priority controls. Owns
/// the tree, filter, selection and folder expansion; the sheet only owns the
/// files themselves.
struct AddTorrentFilesSection: View {
    @Binding var addFiles: [TorrentAddFile]

    @State private var fileFilter = ""
    /// Built only when the file set or filter changes, so toggling a checkbox or
    /// changing a priority doesn't rebuild the tree and collapse its folders.
    @State private var fileTree: [AddTorrentFileNode] = []
    /// Flat lookup for selection expansion, rebuilt with the tree instead of
    /// walking the forest on every body pass.
    @State private var fileNodeByID: [String: AddTorrentFileNode] = [:]
    /// Every folder starts expanded; collapsing one only affects this session
    /// until the file or filter changes again.
    @State private var expandedFolderIDs: Set<String> = []
    /// Native list selection. Folder IDs expand to their descendant files when
    /// a bulk action runs, so selecting a directory changes its files too.
    @State private var selectedNodeIDs: Set<String> = []
    /// Persisted so collapsing the file list once keeps it collapsed.
    @AppStorage(PreferenceKeys.addTorrentFilesExpanded) private var filesExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    filesExpanded.toggle()
                    if !filesExpanded { clearFileSelection() }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(filesExpanded ? 90 : 0))
                    AddTorrentSectionLabel(title: "Files", systemImage: "doc.on.doc")
                    Spacer()
                    Text(selectionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(filesExpanded ? "Hide files" : "Show files")
            .accessibilityValue(filesExpanded ? "Expanded" : "Collapsed")
            .help(filesExpanded ? "Hide the file list" : "Show the file list")

            if filesExpanded {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        fileFilterField
                        HStack(spacing: 6) {
                            Button("Download All") { setAllWanted(true) }
                            Divider().frame(height: 12)
                            Button("None") { setAllWanted(false) }
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }

                    if !selectedTargetFileIndices.isEmpty {
                        fileBulkActions
                    }

                    if filteredFileIndices.isEmpty {
                        Text("No files match the filter.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    } else {
                        fileList
                    }
                }
                .padding(8)
                .background(InsetCardBackground())
                .onChange(of: fileFilter) { _, _ in
                    rebuildTree()
                    selectedNodeIDs.removeAll()
                }

                if !addFiles.isEmpty, wantedFiles.isEmpty {
                    Text("No files selected. The torrent will be added with every file skipped.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // A different `.torrent` brings a different file set; checkbox and
        // priority edits keep the paths, so they don't reset the tree.
        .onChange(of: addFiles.map(\.pathString), initial: true) { _, _ in
            fileFilter = ""
            clearFileSelection()
            rebuildTree()
        }
    }

    private var fileList: some View {
        List(selection: $selectedNodeIDs) {
            ForEach(visibleRows) { row in
                fileNodeRow(row.node, depth: row.depth)
                    .tag(row.node.id)
                    .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    .contextMenu { fileContextMenu(for: row.node) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .focusEffectDisabled()
        .environment(\.defaultMinListRowHeight, addFileRowHeight)
        .frame(height: filesListHeight)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private func fileNodeRow(_ node: AddTorrentFileNode, depth: Int) -> some View {
        Group {
            switch node.kind {
            case .file(let index):
                AddTorrentFileRow(
                    file: $addFiles[index],
                    name: node.name,
                    isSelected: selectedNodeIDs.contains(node.id))
            case .folder:
                let wantedCount = node.fileIndices.filter { addFiles[$0].wanted }.count
                AddTorrentFolderRow(
                    name: node.name,
                    size: node.fileIndices.reduce(0) { $0 + addFiles[$1].length },
                    allWanted: wantedCount == node.fileIndices.count,
                    anyWanted: wantedCount > 0,
                    choice: folderPriorityChoice(node),
                    isExpanded: expandedFolderIDs.contains(node.id),
                    isSelected: selectedNodeIDs.contains(node.id),
                    onToggleExpansion: { toggleFolder(node) },
                    onToggle: {
                        let allWanted = node.fileIndices.allSatisfy { addFiles[$0].wanted }
                        setWanted(!allWanted, for: Set(node.fileIndices))
                    },
                    onPriority: { applyPriority($0, to: Set(node.fileIndices)) })
            }
        }
        .padding(.leading, CGFloat(depth) * 16)
    }

    /// Flattens the tree to the rows currently visible. We keep this instead of
    /// `OutlineGroup` so every folder can start expanded and the chevron sits
    /// where the row wants it.
    private var visibleRows: [VisibleFileRow] {
        var rows: [VisibleFileRow] = []
        func visit(_ nodes: [AddTorrentFileNode], depth: Int) {
            for node in nodes {
                rows.append(VisibleFileRow(node: node, depth: depth))
                if node.isFolder, expandedFolderIDs.contains(node.id), let children = node.children {
                    visit(children, depth: depth + 1)
                }
            }
        }
        visit(fileTree, depth: 0)
        return rows
    }

    private func toggleFolder(_ node: AddTorrentFileNode) {
        withAnimation(.snappy(duration: 0.15)) {
            if expandedFolderIDs.contains(node.id) {
                expandedFolderIDs.remove(node.id)
                selectedNodeIDs.subtract(Set(node.children?.flatMap(\.nodeIDs) ?? []))
            } else {
                expandedFolderIDs.insert(node.id)
            }
        }
    }

    /// A folder's priority chip is uniform only when every descendant is wanted
    /// with the same priority. Some/varies shows the mixed state; all skipped
    /// shows Skip.
    private func folderPriorityChoice(_ node: AddTorrentFileNode) -> FilePriorityChoice? {
        let members = node.fileIndices.map { addFiles[$0] }
        if members.allSatisfy({ !$0.wanted }) { return .skip }
        guard members.allSatisfy(\.wanted), let first = members.first else { return nil }
        return members.allSatisfy { $0.priority == first.priority }
            ? FilePriorityChoice(wanted: true, priority: first.priority)
            : nil
    }

    /// Bulk actions for the highlighted rows. Appears only while rows are
    /// selected, so the checkbox and priority are the primary per-file controls.
    private var fileBulkActions: some View {
        HStack(spacing: 8) {
            Text("\(selectedTargetFileIndices.count) files selected")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                Button("Download") { setWanted(true, for: selectedTargetFileIndices) }
                Divider().frame(height: 12)
                Button("Skip") { setWanted(false, for: selectedTargetFileIndices) }
                Menu("Priority") {
                    priorityMenuItems(ids: selectedTargetFileIndices)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            Button {
                clearFileSelection()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear selection")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private func priorityMenuItems(ids: Set<Int>) -> some View {
        ForEach(FilePriorityChoice.allCases, id: \.self) { choice in
            Button {
                applyPriority(choice, to: ids)
            } label: {
                Label(choice.displayLabel, systemImage: choice.systemImage)
            }
        }
    }

    @ViewBuilder
    private func fileContextMenu(for node: AddTorrentFileNode) -> some View {
        // Right-clicking a selected row acts on the whole selection; right-clicking
        // an unselected row acts on that row. Folder rows cover their descendants.
        let ids =
            selectedNodeIDs.contains(node.id)
            ? selectedTargetFileIndices : Set(node.fileIndices)
        Button("Download") { setWanted(true, for: ids) }
        Button("Skip") { setWanted(false, for: ids) }
        Divider()
        Menu("Priority") {
            priorityMenuItems(ids: ids)
        }
    }

    /// The system search field, with a clear button beside it: the stock
    /// rounded field has no clear affordance on macOS.
    private var fileFilterField: some View {
        HStack(spacing: 4) {
            TextField("Filter Files", text: $fileFilter)
                .textFieldStyle(.roundedBorder)
            if !fileFilter.isEmpty {
                Button {
                    fileFilter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear file filter")
            }
        }
    }

    private func rebuildTree() {
        let tree = AddTorrentFileNode.tree(from: filteredFileIndices.map { addFiles[$0] })
        fileTree = tree
        fileNodeByID = Self.nodeMap(from: tree)
        expandedFolderIDs = Set(tree.flatMap(\.folderIDs))
    }

    private static func nodeMap(
        from nodes: [AddTorrentFileNode]
    ) -> [String: AddTorrentFileNode] {
        var result: [String: AddTorrentFileNode] = [:]
        func visit(_ nodes: [AddTorrentFileNode]) {
            for node in nodes {
                result[node.id] = node
                if let children = node.children { visit(children) }
            }
        }
        visit(nodes)
        return result
    }

    private var filteredFileIndices: [Int] {
        let query = fileFilter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Array(addFiles.indices) }
        return addFiles.indices.filter {
            addFiles[$0].pathString.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedTargetFileIndices: Set<Int> {
        selectedNodeIDs.reduce(into: Set<Int>()) { result, id in
            if let node = fileNodeByID[id] {
                result.formUnion(node.fileIndices)
            }
        }
    }

    private var filesListHeight: CGFloat {
        let rows = min(max(visibleRows.count, 5), 8)
        return CGFloat(rows) * addFileRowHeight
    }

    private var wantedFiles: [TorrentAddFile] {
        addFiles.filter(\.wanted)
    }

    private var selectionSummary: String {
        let size = ColumnFormatters.humanizedSize(wantedFiles.reduce(0) { $0 + $1.length })
        return "\(wantedFiles.count) of \(addFiles.count) files, \(size)"
    }

    private func setAllWanted(_ wanted: Bool) {
        for index in addFiles.indices {
            addFiles[index].wanted = wanted
        }
    }

    private func clearFileSelection() {
        selectedNodeIDs.removeAll()
    }

    private func setWanted(_ wanted: Bool, for ids: Set<Int>) {
        for index in ids where addFiles.indices.contains(index) {
            addFiles[index].wanted = wanted
        }
    }

    private func applyPriority(_ choice: FilePriorityChoice, to ids: Set<Int>) {
        for index in ids where addFiles.indices.contains(index) {
            if let priority = choice.priority {
                addFiles[index].wanted = true
                addFiles[index].priority = priority
            } else {
                addFiles[index].wanted = false
            }
        }
    }
}

/// Shared inset-card surface for the Add Torrent sheet: one system fill and
/// the system separator, so every box matches in light and dark mode.
struct InsetCardBackground: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.quaternary)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor)))
    }
}

/// A section heading in the Add Torrent sheet.
struct AddTorrentSectionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }
}
