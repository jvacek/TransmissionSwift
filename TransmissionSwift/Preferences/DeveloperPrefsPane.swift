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
                    Label("Snapshots", systemImage: "camera")
                    Text(
                        "Snapshot the connected daemon's state into one JSON file for bug reports or AI agents. Torrent names are kept so you can refer to specific torrents; tracker hosts, peer IPs, paths, and timestamps are scrubbed by default."
                    )
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Toggle("Only capture torrents visible with current filters", isOn: $respectFilters)
                Toggle("Limit torrent count", isOn: $limitEnabled)
                if limitEnabled {
                    LabeledContent("Max torrents") {
                        HStack {
                            TextField("", value: $limitValue, format: .number)
                                .frame(width: 52)
                            Stepper("", value: $limitValue, in: 1...500, step: 1)
                                .labelsHidden()
                        }
                    }
                }
            } header: {
                Text("Scope")
            } footer: {
                Text(
                    "Defaults capture the 10 torrents you're currently looking at (filters + sort order). Turn both off to capture everything."
                )
            }
            Section {
                Toggle("Include torrent names", isOn: $includeNames)
                Toggle("Anonymize tracker names", isOn: $anonymizeTrackers)
                Toggle("Include infohashes", isOn: $includeHashes)
                Toggle("Preserve timestamps", isOn: $preserveTimestamps)
            } header: {
                Text("Anonymization")
            } footer: {
                Text(
                    "Names are kept so you can point at a specific torrent. Tracker hosts are fuzzed by default — turn off to keep them real (passkeys are always stripped). Infohashes and timestamps are fuzzed/shifted unless enabled."
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
                        Text(isCapturing ? "Capturing…" : "Capture Snapshot…")
                    }
                }
                .disabled(isCapturing || !isConnected)
                .accessibilityIdentifier("captureSnapshotButton")
            } footer: {
                Text(
                    isConnected
                        ? "Captures the currently connected server's state."
                        : "Connect to a server first — capture needs a live connection."
                )
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, alignment: .top)
        .alert(item: $captureResult) { result in
            switch result {
            case .saved(let url, let capture):
                Alert(
                    title: Text("Snapshot Saved"),
                    message: Text(
                        "Captured \(capture.torrentCount) of \(torrentStore.torrents.count) torrents from \(torrentStore.downloadDirectory ?? "the connected server").\n\(capture.summary.summaryText)\n\n\(url.path)"
                    )
                )
            case .failed(let message):
                Alert(title: Text("Capture Failed"), message: Text(message))
            }
        }
    }

    private var isConnected: Bool {
        if case .connected = torrentStore.connection { return true }
        return false
    }

    private func captureSnapshot() {
        let panel = NSSavePanel()
        panel.title = "Save Snapshot"
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

#Preview("Developer — Connected") {
    DeveloperPrefsPane()
        .environment(prefsPreviewStore)
        .environment(TagColorStore())
        .frame(minWidth: 620, minHeight: 520)
}
