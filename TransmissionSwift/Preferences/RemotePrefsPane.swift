import SwiftUI
import TransmissionCore

struct RemotePrefsPane: View {
    @AppStorage("remoteAccessEnabled") private var remoteEnabled = false
    @AppStorage("remotePort") private var remotePort = 9091
    @AppStorage("remoteRequireAuth") private var requireAuth = false
    @AppStorage("remoteUsername") private var remoteUsername = ""
    @AppStorage("remoteAllowList") private var allowList = ""

    var body: some View {
        Form {
            Section {
                Toggle("Enable remote access", isOn: $remoteEnabled)
                if remoteEnabled {
                    LabeledContent("Port") {
                        TextField("Port", value: $remotePort, format: .number.grouping(.never))
                            .frame(width: 80)
                    }
                    Toggle("Require authentication", isOn: $requireAuth)
                    if requireAuth {
                        TextField("Username", text: $remoteUsername)
                    }
                    LabeledContent("Allow addresses") {
                        TextField("Comma-separated IPs or *", text: $allowList)
                            .font(.monospaced(.body)())
                    }
                }
            } header: {
                Text("Web Interface")
            } footer: {
                Text(
                    "These control the daemon's built-in web interface. They are daemon settings.json configuration and can't be changed over the RPC in Transmission 4.0.6 — edit them on the server."
                )
            }
            .disabled(true)
        }
        .formStyle(.grouped)
    }
}

#Preview("Remote") {
    RemotePrefsPane()
        .frame(width: 480, height: 400)
}
