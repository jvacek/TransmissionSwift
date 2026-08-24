import SwiftUI
import TransmissionCore

struct GeneralPrefsPane: View {
    @AppStorage("showAddDialogBeforeAdding") private var showAddDialog = true
    @AppStorage("startMinimized") private var startMinimized = false
    @AppStorage("badgeAppIcon") private var badgeAppIcon = true
    @AppStorage("confirmRemove") private var confirmRemove = true
    @AppStorage("downloadFolder") private var downloadFolder = "~/Downloads"
    @AppStorage("pollingIntervalSeconds") private var pollingInterval: Double = 5.0
    @AppStorage("freeSpaceIntervalSeconds") private var freeSpaceInterval: Double = 60.0
    @AppStorage("fetchTrackerFavicons") private var fetchFavicons = true
    @Environment(FaviconStore.self) private var favicons

    var body: some View {
        Form {
            Section("Downloads") {
                LabeledContent("Default folder") {
                    Text(downloadFolder)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Toggle("Show dialog before adding a torrent", isOn: $showAddDialog)
                    .disabled(true)
            }
            Section("Connection") {
                LabeledContent("Refresh interval") {
                    HStack {
                        TextField("", value: $pollingInterval, format: .number)
                            .frame(width: 52)
                        Stepper("", value: $pollingInterval, in: 1...60, step: 1)
                            .labelsHidden()
                        Text("seconds")
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Free space interval") {
                    HStack {
                        TextField("", value: $freeSpaceInterval, format: .number)
                            .frame(width: 52)
                        Stepper("", value: $freeSpaceInterval, in: 10...3600, step: 10)
                            .labelsHidden()
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
            .disabled(true)
        }
        .formStyle(.grouped)
    }
}

#Preview("General") {
    GeneralPrefsPane()
        .environment(FaviconStore())
        .frame(width: 480, height: 480)
}
