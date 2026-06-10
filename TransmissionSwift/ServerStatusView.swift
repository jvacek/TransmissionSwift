//
//  ServerStatusView.swift
//  TransmissionSwift
//
//  Created by Jonas Vacek on 10/06/2026.
//

import SwiftUI
import TransmissionCore
import TransmissionRPC

struct ServerStatusView: View {
    @Environment(ServerProfileStore.self) private var profileStore

    let profile: ServerProfile

    @State private var connection = ConnectionService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.label)
                    .font(.title2)
                Text(profile.rpcURL?.absoluteString ?? "invalid URL")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let username = profile.username {
                    Text("User: \(username)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Test connection") {
                    Task { await connection.testConnection(to: profile) }
                }
                .disabled(connection.isTesting)
                .accessibilityIdentifier("server.testConnection")
                if connection.isTesting {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            resultView

            Spacer()

            Button("Remove server", role: .destructive) {
                try? profileStore.remove(id: profile.id)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var resultView: some View {
        switch connection.lastResult {
        case .success(let info):
            Label(
                "Connected to Transmission \(info.version) (RPC \(info.rpcVersion))",
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
            .textSelection(.enabled)
        case .failure(let error):
            Label(error.localizedDescription, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        case nil:
            EmptyView()
        }
    }
}
