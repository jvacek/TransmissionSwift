import SwiftUI
import TransmissionCore

struct GeneralPrefsPane: View {
    @AppStorage(PreferenceKeys.showAddDialogBeforeAdding) private var showAddDialog = true
    @AppStorage(PreferenceKeys.deleteTorrentFileAfterAdding) private var deleteTorrentFileAfterAdding = false
    @AppStorage(PreferenceKeys.startMinimized) private var startMinimized = false
    @AppStorage(PreferenceKeys.badgeAppIcon) private var badgeAppIcon = false
    @AppStorage(PreferenceKeys.confirmRemove) private var confirmRemove = true
    @AppStorage(PreferenceKeys.showDonateButton) private var showDonateButton = true
    @AppStorage(PreferenceKeys.showBugReportButton) private var showBugReportButton = true
    @AppStorage(PreferenceKeys.sendCrashReports) private var sendCrashReports = false
    @AppStorage(PreferenceKeys.pollingIntervalSeconds) private var pollingInterval: Double = 5.0
    @AppStorage(PreferenceKeys.activePollingIntervalSeconds) private var activePollingInterval: Double = 1.0
    @AppStorage(PreferenceKeys.freeSpaceIntervalSeconds) private var freeSpaceInterval: Double = 60.0
    @AppStorage(PreferenceKeys.fetchTrackerFavicons) private var fetchFavicons = true
    @Environment(FaviconStore.self) private var favicons

    var body: some View {
        Form {
            Section {
                Toggle("Show dialog before adding a torrent", isOn: $showAddDialog)
                Toggle("Delete .torrent file after adding by default", isOn: $deleteTorrentFileAfterAdding)
            } header: {
                Text("Downloads")
            } footer: {
                Text(
                    "The Add Torrent dialog starts with this option checked; you can turn it off for a single add. Adds that skip the dialog — drag & drop and “Open With” — follow this default directly. Magnet links have no file to delete."
                )
            }
            Section {
                LabeledContent("Refresh interval") {
                    HStack {
                        TextField("", value: $pollingInterval, format: .number.precision(.fractionLength(0)))
                            .frame(width: 52)
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                }
                .help("How often the whole list refreshes, \(rangeText(PollingIntervals.refresh))")
                LabeledContent("Active refresh interval") {
                    HStack {
                        TextField(
                            "", value: $activePollingInterval,
                            format: .number.precision(.fractionLength(0))
                        )
                        .frame(width: 52)
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                }
                .help(
                    "How often transferring torrents and the inspector refresh, \(rangeText(PollingIntervals.active)) and never above the refresh interval"
                )
                LabeledContent("Free space interval") {
                    HStack {
                        TextField(
                            "", value: $freeSpaceInterval,
                            format: .number.precision(.fractionLength(0))
                        )
                        .frame(width: 52)
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                }
                .help("How often free disk space is re-read, \(rangeText(PollingIntervals.freeSpace))")
            } header: {
                Text("Connection")
            } footer: {
                Text(
                    "The list refreshes every “Refresh interval” seconds. While torrents are transferring, they and the inspector refresh at the active interval in between, which is capped at 45 seconds and at the refresh interval. Values are whole seconds."
                )
            }
            Section("Sidebar") {
                Toggle("Fetch tracker favicons", isOn: $fetchFavicons)
                    .onChange(of: fetchFavicons) { _, newValue in
                        favicons.setEnabled(newValue)
                    }
            }
            Section("Application") {
                Toggle("Badge app icon with active count", isOn: $badgeAppIcon)
                Toggle("Start minimized", isOn: $startMinimized)
                Toggle("Confirm before removing", isOn: $confirmRemove)
            }
            Section("Links on status bar") {
                Toggle("Show donate button", isOn: $showDonateButton)
                Toggle("Show bug report button", isOn: $showBugReportButton)
            }
            Section {
                Toggle("Send anonymous crash reports", isOn: $sendCrashReports)
                    .onChange(of: sendCrashReports) { _, newValue in
                        CrashReporting.setConsent(enabled: newValue)
                    }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Crash reports help fix bugs. \(CrashReporting.privacySummary) Off by default.")
            }
        }
        .formStyle(.grouped)
        .onAppear { normalizeIntervals() }
        .onChange(of: pollingInterval) { _, _ in normalizeIntervals() }
        .onChange(of: activePollingInterval) { _, _ in normalizeIntervals() }
        .onChange(of: freeSpaceInterval) { _, _ in normalizeIntervals() }
    }

    /// Keep every field inside the range the service honors, including the
    /// active interval's dependence on the refresh interval. Runs after each
    /// edit so no invalid value is ever stored.
    private func normalizeIntervals() {
        let refresh = PollingIntervals.normalized(pollingInterval, to: PollingIntervals.refresh)
        if refresh != pollingInterval {
            pollingInterval = refresh
        }

        let active = PollingIntervals.incremental(active: activePollingInterval, refresh: refresh)
        if active != activePollingInterval {
            activePollingInterval = active
        }

        let freeSpace = PollingIntervals.normalized(freeSpaceInterval, to: PollingIntervals.freeSpace)
        if freeSpace != freeSpaceInterval {
            freeSpaceInterval = freeSpace
        }
    }

    private func rangeText(_ range: ClosedRange<Double>) -> String {
        "between \(Int(range.lowerBound)) and \(Int(range.upperBound)) seconds"
    }
}

#Preview("General") {
    GeneralPrefsPane()
        .environment(FaviconStore())
        .frame(width: 480, height: 480)
}
