import SwiftUI

struct UpdatesPrefsPane: View {
    @AppStorage("SUEnableAutomaticChecks") private var checkForUpdates = true
    @AppStorage("includePrereleases") private var includePrereleases = false

    var body: some View {
        Form {
            Section {
                Toggle("Check for updates on startup", isOn: $checkForUpdates)
                Toggle("Include pre-release versions", isOn: $includePrereleases)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview("Updates") {
    UpdatesPrefsPane()
        .frame(width: 480, height: 240)
}
