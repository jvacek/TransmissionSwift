import SwiftUI
import TransmissionCore

// MARK: - Session-not-connected gate

/// Shown in place of the Speed / Network / Seeding form while there is no live
/// daemon connection to read or write session settings from.
struct SessionNotConnectedView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Not Connected", systemImage: "bolt.horizontal")
        } description: {
            Text("Connect to a server to change these settings.")
        }
    }
}

// MARK: - Turtle schedule rows

struct TurtleTimeRow: View {
    @Binding var begin: Int
    @Binding var end: Int

    var body: some View {
        HStack(spacing: 4) {
            Text("Active window")
            Spacer()
            HStack(spacing: 2) {
                TimeField(minutes: $begin)
                Text("–").foregroundStyle(.secondary)
                TimeField(minutes: $end)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct TimeField: View {
    @Binding var minutes: Int

    var body: some View {
        DatePicker(
            "",
            selection: dateBinding,
            displayedComponents: .hourAndMinute
        )
        .labelsHidden()
        .frame(width: 88)
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            }
        )
    }
}

struct TurtleScheduleDays: View {
    @Binding var mask: Int

    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        LabeledContent("Active days") {
            HStack(spacing: 4) {
                ForEach(0..<7) { day in
                    let bit = 1 << day
                    Toggle(
                        weekdays[day],
                        isOn: Binding(
                            get: { mask & bit != 0 },
                            set: { on in
                                if on { mask |= bit } else { mask &= ~bit }
                            }
                        )
                    )
                    .toggleStyle(.button)
                    .controlSize(.mini)
                }
            }
        }
    }
}

// MARK: - Session-setting bindings

/// App-target convenience for binding a `SessionSettings` field to the daemon:
/// reads the store's current value (defaulted when disconnected), and writes
/// through `updateSessionSettings` (which diffs to a partial `session-set`).
/// Lives in the app target because `Binding` is SwiftUI.
extension TorrentStore {
    /// The daemon's session settings, falling back to the realistic sample so a
    /// connected-but-still-loading store (or a preview) renders populated forms.
    var effectiveSessionSettings: SessionSettings { sessionSettings ?? .sample }

    func binding(keyPath: WritableKeyPath<SessionSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { self.sessionSettings?[keyPath: keyPath] ?? SessionSettings.sample[keyPath: keyPath] },
            set: { newValue in Task { await self.updateSessionSettings { $0[keyPath: keyPath] = newValue } } }
        )
    }

    func binding(keyPath: WritableKeyPath<SessionSettings, Int>) -> Binding<Int> {
        Binding(
            get: { self.sessionSettings?[keyPath: keyPath] ?? SessionSettings.sample[keyPath: keyPath] },
            set: { newValue in Task { await self.updateSessionSettings { $0[keyPath: keyPath] = newValue } } }
        )
    }

    func binding(keyPath: WritableKeyPath<SessionSettings, Double>) -> Binding<Double> {
        Binding(
            get: { self.sessionSettings?[keyPath: keyPath] ?? SessionSettings.sample[keyPath: keyPath] },
            set: { newValue in Task { await self.updateSessionSettings { $0[keyPath: keyPath] = newValue } } }
        )
    }

    func binding(keyPath: WritableKeyPath<SessionSettings, String>) -> Binding<String> {
        Binding(
            get: { self.sessionSettings?[keyPath: keyPath] ?? SessionSettings.sample[keyPath: keyPath] },
            set: { newValue in Task { await self.updateSessionSettings { $0[keyPath: keyPath] = newValue } } }
        )
    }
}

// MARK: - Preview support

/// Shared stores for the per-pane `#Preview`s (each pane's preview is defined in
/// that pane's own file). Internal so any preferences file can reference them.
/// Previews run on the main actor, so building the `@MainActor` stores at file
/// scope is safe. The connected store backs a mock whose `sessionSettings` is
/// `SessionSettings.sample`, so the connected previews render populated forms.

let prefsPreviewStore: TorrentStore = {
    let store = TorrentStore(service: MockTorrentService())
    store.simulateConnection(.connected)
    return store
}()

let prefsDisconnectedPreviewStore: TorrentStore = {
    let store = TorrentStore(service: MockTorrentService())
    store.simulateConnection(.disconnected(reason: "offline"))
    // The store's init task auto-connects when the mock stream yields; pausing
    // polling before the task runs keeps it in the disconnected state.
    store.pausePolling()
    return store
}()

let prefsPreviewProfileStore: ServerProfileStore = {
    let store = ServerProfileStore(
        fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("servers-preview-\(UUID().uuidString).json"))
    try? store.add(ServerProfile(label: "Home NAS", host: "192.168.1.2", port: 9091))
    try? store.add(ServerProfile(label: "Seedbox", host: "seedbox.example.com", port: 9091))
    try? store.setActive(store.profiles.first!.id)
    return store
}()
