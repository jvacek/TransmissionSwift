//
//  TransmissionSwiftApp.swift
//  TransmissionSwift
//
//  Created by Jonas Vacek on 10/06/2026.
//

import SwiftUI
import TransmissionCore

@main
struct TransmissionSwiftApp: App {
    @State private var profileStore: ServerProfileStore = {
        // UI tests pass this flag to start from a clean, throwaway profile list.
        if CommandLine.arguments.contains("--ephemeral-profiles") {
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ephemeral-profiles-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent("servers.json")
            return ServerProfileStore(fileURL: fileURL)
        }
        let fileURL =
            (try? ServerProfileStore.defaultFileURL())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("servers.json")
        return ServerProfileStore(fileURL: fileURL)
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(profileStore)
        }
    }
}
