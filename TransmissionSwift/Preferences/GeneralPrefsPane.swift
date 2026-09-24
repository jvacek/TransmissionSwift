import SwiftUI
import TransmissionCore

struct GeneralPrefsPane: View {
    @AppStorage("showAddDialogBeforeAdding") private var showAddDialog = true
    @AppStorage("startMinimized") private var startMinimized = false
    @AppStorage("badgeAppIcon") private var badgeAppIcon = false
    @AppStorage("confirmRemove") private var confirmRemove = true
    @AppStorage("pollingIntervalSeconds") private var pollingInterval: Double = 5.0
    @AppStorage("freeSpaceIntervalSeconds") private var freeSpaceInterval: Double = 60.0
    @AppStorage("fetchTrackerFavicons") private var fetchFavicons = true
    @Environment(FaviconStore.self) private var favicons

    var body: some View {
        Form {
            Section("Downloads") {
                Toggle("Show dialog before adding a torrent", isOn: $showAddDialog)
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
        }
        .formStyle(.grouped)
    }
}

#Preview("General") {
    GeneralPrefsPane()
        .environment(FaviconStore())
        .frame(width: 480, height: 480)
}
