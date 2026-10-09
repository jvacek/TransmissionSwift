import SwiftUI
import TransmissionCore

/// Names the Shortcut that "Send to Shortcut" runs. A sandboxed app can't
/// enumerate the user's shortcuts, so the exact name is typed here.
struct ShortcutsPrefsPane: View {
    @AppStorage(PreferenceKeys.sendToShortcutName) private var shortcutName = ""

    var body: some View {
        Form {
            Section {
                TextField("Exact name of the shortcut", text: $shortcutName)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Send to Shortcut")
            } footer: {
                Text(
                    "Right-click a torrent and pick “Send to \(name)” to run this shortcut, passing the torrent's transmissionswift:// link as text. The shortcut must accept text input."
                )
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var name: String {
        let trimmed = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Shortcut" : trimmed
    }
}

#Preview("Shortcuts") {
    ShortcutsPrefsPane()
        .frame(width: 620, height: 320)
}
