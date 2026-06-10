//
//  ContentView.swift
//  TransmissionSwift
//
//  Created by Jonas Vacek on 10/06/2026.
//

import SwiftUI
import TransmissionCore

struct ContentView: View {
    @Environment(ServerProfileStore.self) private var profileStore

    var body: some View {
        Group {
            if let profile = profileStore.profiles.first {
                ServerStatusView(profile: profile)
            } else {
                AddServerForm()
            }
        }
        .frame(minWidth: 420, minHeight: 320)
    }
}
