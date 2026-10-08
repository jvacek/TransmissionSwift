import AppKit
import SwiftUI
import TransmissionCore

/// Bottom 28pt status bar, attached to the main window via `.safeAreaInset`.
/// Wears `.regularMaterial` — never `.glassEffect`, since the status bar lives
/// in the content layer, not the navigation layer. (LG: glass is for chrome.)
struct StatusBarView: View {
    @Environment(TorrentStore.self) private var store
    @Environment(ServerProfileStore.self) private var profileStore
    @Environment(\.openURL) private var openURL
    @AppStorage(PreferenceKeys.badgeAppIcon) private var badgeAppIcon = false
    @AppStorage(PreferenceKeys.showDonateButton) private var showDonateButton = true
    @AppStorage(PreferenceKeys.showBugReportButton) private var showBugReportButton = true
    @State private var showServerStats = false

    var body: some View {
        HStack(spacing: 14) {
            supportButtons
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
        .onAppear { updateDockBadge() }
        .onChange(of: activeCount) { _, _ in updateDockBadge() }
        .onChange(of: badgeAppIcon) { _, _ in updateDockBadge() }
    }

    @ViewBuilder
    private var supportButtons: some View {
        if showDonateButton || showBugReportButton {
            HStack(spacing: 10) {
                if showDonateButton { donateButton }
                if showBugReportButton { reportBugButton }
            }
            Divider().frame(height: 14)
        }
    }

    private var reportBugButton: some View {
        Button {
            if let url = BugReport.url(daemonVersion: store.session.daemonVersion) {
                openURL(url)
            }
        } label: {
            Image(systemName: "ladybug")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("Report a bug on GitHub")
        .foregroundStyle(Color(NSColor.secondaryLabelColor))
        .accessibilityIdentifier("statusBar.reportBug")
    }

    private var donateButton: some View {
        Button {
            if let url = URL(string: "https://transmissionswift.jvacek.eu/donate/") {
                openURL(url)
            }
        } label: {
            Image(systemName: "heart")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("Support TransmissionSwift")
        .foregroundStyle(.pink)
        .accessibilityIdentifier("statusBar.donate")
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
            Text("\(store.list.torrents.count) torrents · \(activeCount) active")
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
                Task { await store.session.toggleAlternativeSpeed() }
            } label: {
                Image(systemName: store.session.isAlternativeSpeedEnabled ? "tortoise.fill" : "tortoise")
            }
            .buttonStyle(.borderless)
            .disabled(!store.actionsEnabled)
            .help("Alternative speed limits")
            .foregroundStyle(
                store.session.isAlternativeSpeedEnabled
                    ? Color(NSColor.controlAccentColor) : Color(NSColor.secondaryLabelColor)
            )
            if let freeSpace = store.session.freeSpace {
                Divider().frame(height: 14)
                Button {
                    Task { await store.session.refreshFreeSpace() }
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
        guard let s = store.session.settings else { return nil }
        if s.altSpeedEnabled { return s.altSpeedDownKBps }
        if s.downLimited { return s.downLimitKBps }
        return nil
    }
    private var effectiveUpCapKBps: Int? {
        guard let s = store.session.settings else { return nil }
        if s.altSpeedEnabled { return s.altSpeedUpKBps }
        if s.upLimited { return s.upLimitKBps }
        return nil
    }

    private var activeCount: Int {
        store.list.torrents.filter { $0.status == .downloading || $0.status == .seeding }.count
    }

    /// Mirrors the active-torrent count onto the Dock icon when the
    /// "Badge app icon" pref is on; cleared otherwise.
    private func updateDockBadge() {
        NSApp.dockTile.badgeLabel = (badgeAppIcon && activeCount > 0) ? "\(activeCount)" : ""
    }
    private var totalDown: Int64 { store.list.torrents.reduce(0) { $0 + $1.downloadSpeed } }
    private var totalUp: Int64 { store.list.torrents.reduce(0) { $0 + $1.uploadSpeed } }
    private var overallRatio: Double {
        guard !store.list.torrents.isEmpty else { return 0 }
        return store.list.torrents.map(\.ratio).reduce(0, +) / Double(store.list.torrents.count)
    }
}
