import SwiftUI
import TransmissionCore

struct GeneralPrefsPane: View {
    @AppStorage(PreferenceKeys.showAddDialogBeforeAdding) private var showAddDialog = true
    @AppStorage(PreferenceKeys.deleteTorrentFileAfterAdding) private var deleteTorrentFileAfterAdding = false
    @AppStorage("startMinimized") private var startMinimized = false
    @AppStorage("badgeAppIcon") private var badgeAppIcon = false
    @AppStorage("confirmRemove") private var confirmRemove = true
    @AppStorage("showDonateButton") private var showDonateButton = true
    @AppStorage("showBugReportButton") private var showBugReportButton = true
    @AppStorage("sendCrashReports") private var sendCrashReports = false
    @AppStorage("pollingIntervalSeconds") private var pollingInterval: Double = 5.0
    @AppStorage("freeSpaceIntervalSeconds") private var freeSpaceInterval: Double = 60.0
    @AppStorage("fetchTrackerFavicons") private var fetchFavicons = true
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
            Section("Connection") {
                LabeledContent("Refresh interval") {
                    HStack {
                        TextField("", value: $pollingInterval, format: .number)
                            .frame(width: 52)
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Free space interval") {
                    HStack {
                        TextField("", value: $freeSpaceInterval, format: .number)
                            .frame(width: 52)
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                }
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
    }
}

#Preview("General") {
    GeneralPrefsPane()
        .environment(FaviconStore())
        .frame(width: 480, height: 480)
}
