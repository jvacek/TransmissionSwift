// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import TransmissionCore

/// Which servers a mapping applies to: all, remote, local, or a checklist.
struct MappingScopePicker: View {
    @Binding var scope: MappingServerScope

    /// The servers the "Selected Servers" checklist offers.
    @Environment(ServerProfileStore.self) private var profileStore

    private enum Choice: Hashable { case all, remote, local, selected }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Applies to")
                Spacer()
                Picker("Applies to", selection: choice) {
                    Text("All Servers").tag(Choice.all)
                    Text("All Remote Servers").tag(Choice.remote)
                    Text("All Local Servers").tag(Choice.local)
                    Text("Selected Servers").tag(Choice.selected)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Text(help)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if case .only = scope {
                if profileStore.profiles.isEmpty {
                    Text("No servers configured yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(profileStore.profiles) { profile in
                            Toggle(isOn: serverToggle(profile.id)) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(profile.label)
                                    Text("\(profile.host):\(profile.port)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospaced()
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    if !scope.targetsAnyServer {
                        Text("Select at least one server.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private var choice: Binding<Choice> {
        Binding(
            get: {
                switch scope {
                case .all: return .all
                case .remote: return .remote
                case .local: return .local
                case .only: return .selected
                }
            },
            set: { choice in
                switch choice {
                case .all:
                    scope = .all
                case .remote:
                    scope = .remote
                case .local:
                    scope = .local
                case .selected:
                    if case .only = scope { return }
                    // Seed with every current server so unchecking one is one
                    // click; servers added later won't be included.
                    scope = .only(Set(profileStore.profiles.map(\.id)))
                }
            })
    }

    private func serverToggle(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: {
                if case .only(let ids) = scope { return ids.contains(id) }
                return true
            },
            set: { on in
                guard case .only(var ids) = scope else { return }
                if on { ids.insert(id) } else { ids.remove(id) }
                scope = .only(ids)
            })
    }

    /// Explains what the chosen scope matches, so the local/remote split is
    /// explicit: "remote" is defined as the complement of a local server.
    private var help: String {
        switch scope {
        case .all:
            return "Matches every server, including servers you add later."
        case .remote:
            return
                "Matches servers outside your local network, such as a seedbox or a public address. Includes servers you add later."
        case .local:
            return
                "Matches localhost and your local network: private addresses (10.x, 172.16–31.x, 192.168.x), link-local addresses, and .local names. Includes servers you add later."
        case .only:
            return "Matches only the servers you tick below."
        }
    }
}

extension MappingServerScope {
    /// A "Selected Servers" scope must name at least one server; the others
    /// always match something, including servers added later.
    var targetsAnyServer: Bool {
        if case .only(let ids) = self { return !ids.isEmpty }
        return true
    }
}
