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
    let mockMode: Bool

    var body: some View {
        if mockMode {
            MainWindow(mockMode: mockMode)
        } else if let profile = profileStore.activeProfile {
            // The real-RPC path lands in slice 7. Until then this stays at the
            // single-profile connectivity check from the first slice.
            ServerStatusView(profile: profile)
                .frame(minWidth: 420, minHeight: 320)
        } else {
            AddServerForm()
                .frame(minWidth: 420, minHeight: 320)
        }
    }
}
