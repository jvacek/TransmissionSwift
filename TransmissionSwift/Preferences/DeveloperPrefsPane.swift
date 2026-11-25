// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

//
//  DeveloperPrefsPane.swift
//  TransmissionSwift
//

import AppKit
import SwiftUI
import TransmissionCore
import UniformTypeIdentifiers

/// Developer tooling, tucked away in Preferences. Currently just snapshot
/// capture: dump the connected daemon's full state as an anonymized JSON file
/// for bug reports / agent repros (see `doc/snapshot-replay.md`).
struct DeveloperPrefsPane: View {
    @Environment(TorrentStore.self) private var torrentStore
    @Environment(TagColorStore.self) private var tagColors

    // Per-capture options — defaults favor identifying-friendly, focused
    // captures; never persisted.
    @State private var includeNames = true
    @State private var anonymizeTrackers = true
    @State private var includeHashes = false
    @State private var preserveTimestamps = false
    @State private var respectFilters = true
    @State private var limitEnabled = true
    @State private var limitValue = 10
    @State private var isCapturing = false
    @State private var captureResult: CaptureResult?

    private enum CaptureResult: Identifiable {
        case saved(url: URL, result: SnapshotCaptureResult)
        case failed(String)

        var id: String {
            switch self {
            case .saved(let url, _): return "saved-\(url.path)"
            case .failed(let message): return "failed-\(message)"
            }
        }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label(L10n.text("Snapshots"), systemImage: "camera")
                    Text(
                        L10n.text(
                            "Snapshot the connected daemon's state into one JSON file for bug reports or AI agents. Torrent names are kept so you can refer to specific torrents; tracker hosts, peer IPs, paths, and timestamps are scrubbed by default."
                        )
                    )
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle(L10n.text("Only capture torrents visible with current filters"), isOn: $respectFilters)
                Toggle(L10n.text("Limit torrent count"), isOn: $limitEnabled)
                if limitEnabled {
                    LabeledContent(L10n.text("Max torrents")) {
                        TextField("", value: $limitValue, format: .number)
                            .frame(width: 52)
                    }
                }
            } header: {
                Text(L10n.text("Scope"))
            } footer: {
                Text(
                    L10n.text(
                        "Defaults capture the 10 torrents you're currently looking at (filters + sort order). Turn both off to capture everything."
                    )
                )
            }
            Section {
                Toggle(L10n.text("Include torrent names"), isOn: $includeNames)
                Toggle(L10n.text("Anonymize tracker names"), isOn: $anonymizeTrackers)
                Toggle(L10n.text("Include infohashes"), isOn: $includeHashes)
                Toggle(L10n.text("Preserve timestamps"), isOn: $preserveTimestamps)
            } header: {
                Text(L10n.text("Anonymization"))
            } footer: {
                Text(
                    L10n.text(
                        "Names are kept so you can point at a specific torrent. Tracker hosts are fuzzed by default — turn off to keep them real (passkeys are always stripped). Infohashes and timestamps are fuzzed/shifted unless enabled."
                    )
                )
            }
            Section {
                Button {
                    captureSnapshot()
                } label: {
                    HStack {
                        if isCapturing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "camera.fill")
                        }
                        Text(isCapturing ? L10n.text("Capturing…") : L10n.text("Capture Snapshot…"))
                    }
                }
                .disabled(isCapturing || !isConnected)
                .accessibilityIdentifier("captureSnapshotButton")
            } footer: {
                Text(
                    isConnected
                        ? L10n.text("Captures the currently connected server's state.")
                        : L10n.text("Connect to a server first — capture needs a live connection.")
                )
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, alignment: .top)
        .alert(item: $captureResult) { result in
            switch result {
            case .saved(let url, let capture):
                Alert(
                    title: Text(L10n.text("Snapshot Saved")),
                    message: Text(
                        L10n.format(
                            "Captured %lld of %lld torrents from %@.\n%@\n\n%@", Int64(capture.torrentCount),
                            Int64(torrentStore.list.torrents.count),
                            torrentStore.list.downloadDirectory ?? L10n.text("the connected server"),
                            capture.summary.summaryText, url.path)
                    )
                )
            case .failed(let message):
                Alert(title: Text(L10n.text("Capture Failed")), message: Text(message))
            }
        }
    }

    private var isConnected: Bool {
        if case .connected = torrentStore.connection { return true }
        return false
    }

    private func captureSnapshot() {
        let panel = NSSavePanel()
        panel.title = L10n.text("Save Snapshot")
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = Self.defaultSnapshotName()
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isCapturing = true
        Task { @MainActor in
            defer { isCapturing = false }
            do {
                let options = SnapshotRedactionOptions(
                    includeNames: includeNames,
                    anonymizeTrackers: anonymizeTrackers,
                    includeHashes: includeHashes,
                    preserveTimestamps: preserveTimestamps,
                    maxTorrents: limitEnabled ? limitValue : nil,
                    respectFilters: respectFilters
                )
                let result = try await torrentStore.captureSnapshot(
                    to: url, options: options, tagColors: tagColors.colors)
                captureResult = .saved(url: url, result: result)
            } catch {
                captureResult = .failed(error.localizedDescription)
            }
        }
    }

    private static func defaultSnapshotName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "snapshot-\(formatter.string(from: Date())).json"
    }
}

#if DEBUG
#Preview("Developer — Connected") {
    DeveloperPrefsPane()
        .environment(prefsPreviewStore)
        .environment(TagColorStore())
        .frame(minWidth: 620, minHeight: 520)
}
#endif
