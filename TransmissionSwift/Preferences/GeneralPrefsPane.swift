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
    @AppStorage(PreferenceKeys.pollingIntervalSeconds) private var pollingInterval: Double = PollingIntervals
        .defaultRefresh
    @AppStorage(PreferenceKeys.incrementalPollingIntervalSeconds) private var incrementalPollingInterval: Double =
        PollingIntervals.defaultIncremental
    @AppStorage(PreferenceKeys.freeSpaceIntervalSeconds) private var freeSpaceInterval: Double = PollingIntervals
        .defaultFreeSpace
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
                secondsRow(
                    "Refresh interval", value: $pollingInterval,
                    help: "How often the whole list refreshes, \(rangeText(PollingIntervals.refresh))")
                secondsRow(
                    "Incremental refresh interval", value: $incrementalPollingInterval,
                    help:
                        "How often changed torrents refresh, \(rangeText(PollingIntervals.incremental)) and never above the refresh interval"
                )
                secondsRow(
                    "Free space interval", value: $freeSpaceInterval,
                    help: "How often free disk space is re-read, \(rangeText(PollingIntervals.freeSpace))")
            } header: {
                Text("Connection")
            } footer: {
                Text(
                    "The full list refreshes every “Refresh interval” seconds. Changed torrents, and the inspector, refresh at the incremental interval in between, which is capped at 45 seconds and at the refresh interval. Values are whole seconds."
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
        .onChange(of: incrementalPollingInterval) { _, _ in normalizeIntervals() }
        .onChange(of: freeSpaceInterval) { _, _ in normalizeIntervals() }
    }

    /// Keep every field inside the range the service honors, including the
    /// incremental interval's dependence on the refresh interval. Runs after
    /// each edit so no invalid value is ever stored.
    private func normalizeIntervals() {
        let original = (pollingInterval, incrementalPollingInterval, freeSpaceInterval)

        let refresh = PollingIntervals.normalized(pollingInterval, to: PollingIntervals.refresh)
        if refresh != pollingInterval {
            pollingInterval = refresh
        }

        let incremental = PollingIntervals.clampedIncremental(
            incrementalPollingInterval, refresh: refresh)
        if incremental != incrementalPollingInterval {
            incrementalPollingInterval = incremental
        }

        let freeSpace = PollingIntervals.normalized(freeSpaceInterval, to: PollingIntervals.freeSpace)
        if freeSpace != freeSpaceInterval {
            freeSpaceInterval = freeSpace
        }

        // Let a sleeping poll loop pick the new value up now instead of after
        // the old interval has elapsed.
        if (pollingInterval, incrementalPollingInterval, freeSpaceInterval) != original {
            NotificationCenter.default.post(name: PollingIntervals.changed, object: nil)
        }
    }

    /// A whole-seconds field with a fixed unit slot, so every interval row has
    /// the same geometry and the numbers line up with each other and with the
    /// switches in the sections above. Laid out by hand because a
    /// `LabeledContent` sizes its content column instead of reaching the row's
    /// trailing edge, which left the fields short of the switches.
    private func secondsRow(_ title: String, value: Binding<Double>, help: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
            Spacer(minLength: 24)
            TextField("", value: value, format: .number.precision(.fractionLength(0)))
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 60)
                .accessibilityLabel(title)
            Text(value.wrappedValue == 1 ? "second" : "seconds")
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
        }
        .help(help)
    }

    private func rangeText(_ range: ClosedRange<Double>) -> String {
        "between \(Int(range.lowerBound)) and \(Int(range.upperBound)) seconds"
    }
}

#Preview("General") {
    GeneralPrefsPane()
        .environment(FaviconStore())
        .frame(width: 480, height: 1080)
}
