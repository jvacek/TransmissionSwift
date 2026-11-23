// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import TransmissionCore

/// The toolbar's server switcher: pick the active server, or open Server
/// Settings.
struct ServerSwitcherMenu: View {
    @Environment(ServerProfileStore.self) private var profileStore
    let onOpenSettings: () -> Void

    private var name: String { profileStore.activeProfile?.label ?? "No Server" }

    var body: some View {
        Menu {
            ForEach(profileStore.profiles) { profile in
                Toggle(
                    isOn: Binding(
                        get: { profileStore.activeProfile?.id == profile.id },
                        set: { on in if on { try? profileStore.setActive(profile.id) } }
                    )
                ) {
                    Text(profile.label)
                }
            }
            Divider()
            Button("Server Settings…", action: onOpenSettings)
        } label: {
            // Titled "Server" for the toolbar's Icon and Text caption, but drawn
            // with the server's name: the only place the window shows it, as
            // the title is kept out of the toolbar (see `navigationTitle`).
            Label("Server", systemImage: "server.rack")
                .labelStyle(NameLabelStyle(name: name))
        }
        // Capped so a long name truncates instead of widening the window.
        .frame(maxWidth: 180)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityIdentifier("toolbar.serverSwitcher")
    }
}

/// Draws the label as its icon and the server's name, while the label's own
/// title ("Server") stays the toolbar item's caption.
private struct NameLabelStyle: LabelStyle {
    let name: String

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            Text(name).lineLimit(1)
        }
    }
}
