import SwiftUI
import TransmissionCore

/// Bottom 28pt status bar, attached to the main window via `.safeAreaInset`.
/// Wears `.regularMaterial` — never `.glassEffect`, since the status bar lives
/// in the content layer, not the navigation layer. (LG: glass is for chrome.)
struct StatusBarView: View {
    @Environment(TorrentStore.self) private var store

    var body: some View {
        HStack(spacing: 14) {
            leftCluster
            Spacer(minLength: 8)
            rightCluster
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 28)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var leftCluster: some View {
        HStack(spacing: 10) {
            Button {
                Task { await store.toggleAlternativeSpeed() }
            } label: {
                Image(systemName: store.isAlternativeSpeedEnabled ? "tortoise.fill" : "tortoise")
            }
            .buttonStyle(.borderless)
            .help("Alternative speed limits")

            Text("\(store.torrents.count) torrents · \(activeCount) active")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityIdentifier("statusBar.count")
        }
    }

    private var rightCluster: some View {
        HStack(spacing: 12) {
            Label(totalDown.formattedSpeed, systemImage: "arrow.down")
                .foregroundStyle(.blue)
                .monospacedDigit()
            Label(totalUp.formattedSpeed, systemImage: "arrow.up")
                .foregroundStyle(.green)
                .monospacedDigit()
            Divider().frame(height: 14)
            Label("412 GB free", systemImage: "internaldrive")
                .foregroundStyle(.secondary)
            Text("Ratio \(overallRatio, format: .number.precision(.fractionLength(2)))")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var activeCount: Int {
        store.torrents.filter { $0.status == .downloading || $0.status == .seeding }.count
    }
    private var totalDown: Int64 { store.torrents.reduce(0) { $0 + $1.downloadSpeed } }
    private var totalUp: Int64 { store.torrents.reduce(0) { $0 + $1.uploadSpeed } }
    private var overallRatio: Double {
        guard !store.torrents.isEmpty else { return 0 }
        return store.torrents.map(\.ratio).reduce(0, +) / Double(store.torrents.count)
    }
}
