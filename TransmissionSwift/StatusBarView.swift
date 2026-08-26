import AppKit
import SwiftUI
import TransmissionCore

/// Bottom 28pt status bar, attached to the main window via `.safeAreaInset`.
/// Wears `.regularMaterial` — never `.glassEffect`, since the status bar lives
/// in the content layer, not the navigation layer. (LG: glass is for chrome.)
struct StatusBarView: View {
    @Environment(TorrentStore.self) private var store
    @Environment(ServerProfileStore.self) private var profileStore
    @State private var showServerStats = false

    var body: some View {
        HStack(spacing: 14) {
            switch store.connection {
            case .connecting:
                let name = profileStore.activeProfile?.label ?? "server"
                Text("Connecting to \(name)…")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer(minLength: 8)
            case .awaitingKeychain:
                Text("Waiting for keychain access…")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer(minLength: 8)
            case .disconnected:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Disconnected")
                    .foregroundStyle(.red)
                Spacer(minLength: 8)
            case .connected:
                leftCluster
                Spacer(minLength: 8)
                rightCluster
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var leftCluster: some View {
        HStack(spacing: 10) {
            Button {
                showServerStats.toggle()
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Server statistics")
            .foregroundStyle(Color(NSColor.secondaryLabelColor))
            .accessibilityIdentifier("statusBar.serverStats")
            .popover(isPresented: $showServerStats, arrowEdge: .bottom) {
                ServerStatsPopoverView()
            }
            Text("\(store.torrents.count) torrents · \(activeCount) active")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityIdentifier("statusBar.count")
        }
    }

    private var rightCluster: some View {
        HStack(spacing: 12) {
            speedLabel(total: totalDown, systemImage: "arrow.down", color: .blue, capKBps: effectiveDownCapKBps)
            speedLabel(total: totalUp, systemImage: "arrow.up", color: .green, capKBps: effectiveUpCapKBps)
            Button {
                Task { await store.toggleAlternativeSpeed() }
            } label: {
                Image(systemName: store.isAlternativeSpeedEnabled ? "tortoise.fill" : "tortoise")
            }
            .buttonStyle(.borderless)
            .disabled(!store.actionsEnabled)
            .help("Alternative speed limits")
            .foregroundStyle(
                store.isAlternativeSpeedEnabled ? Color(NSColor.controlAccentColor) : Color(NSColor.secondaryLabelColor)
            )
            if let freeSpace = store.freeSpace {
                Divider().frame(height: 14)
                Button {
                    Task { await store.refreshFreeSpace() }
                } label: {
                    Label(ColumnFormatters.humanizedSize(freeSpace) + " free", systemImage: "internaldrive")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Click to refresh free space")
            }
            Text("Ratio \(overallRatio, format: .number.precision(.fractionLength(2)))")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func speedLabel(total: Int64, systemImage: String, color: Color, capKBps: Int?) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(ColumnFormatters.humanizedSpeed(total))
                .foregroundStyle(color)
            if let capKBps, capKBps > 0 {
                Text("(\(ColumnFormatters.humanizedSpeed(Int64(capKBps) * 1024)))")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .monospacedDigit()
    }

    /// Effective per-torrent speed cap in KB/s, whichever scheme is active:
    /// turtle limits win while `altSpeedEnabled`, otherwise the global limits.
    private var effectiveDownCapKBps: Int? {
        guard let s = store.sessionSettings else { return nil }
        if s.altSpeedEnabled { return s.altSpeedDownKBps }
        if s.downLimited { return s.downLimitKBps }
        return nil
    }
    private var effectiveUpCapKBps: Int? {
        guard let s = store.sessionSettings else { return nil }
        if s.altSpeedEnabled { return s.altSpeedUpKBps }
        if s.upLimited { return s.upLimitKBps }
        return nil
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
