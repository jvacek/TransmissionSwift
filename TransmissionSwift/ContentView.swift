import SwiftUI
import TransmissionCore
import TransmissionRPC

struct ContentView: View {
    @Environment(ServerProfileStore.self) private var profileStore
    @Environment(TorrentStore.self) private var torrentStore
    @Environment(\.scenePhase) private var scenePhase
    /// True when replaying a captured snapshot file (`--snapshot`).
    let snapshotMode: Bool
    /// True for non-interactive sessions (snapshot replay, ephemeral test
    /// profiles) where the first-run splash must not appear.
    let disableOnboarding: Bool

    @State private var connection: ConnectionCoordinator
    @State private var hasAppeared = false
    @State private var showsCrashReportingConsent = false

    init(store: TorrentStore, snapshotMode: Bool, disableOnboarding: Bool) {
        self.snapshotMode = snapshotMode
        self.disableOnboarding = disableOnboarding
        _connection = State(initialValue: ConnectionCoordinator(store: store))
    }

    var body: some View {
        Group {
            if snapshotMode {
                // Replay: frozen, read-only state from the snapshot file. No
                // connect task — the service is already the snapshot source.
                MainWindow()
            } else {
                // Always render the main window — when no profile exists it shows
                // a "No Servers" empty state pointing at Settings, so onboarding
                // lives in one window instead of a separate page. The connect task
                // no-ops until a profile is added (id flips from nil to a UUID).
                MainWindow()
                    .task(id: profileStore.activeProfile?.id) {
                        guard let profile = profileStore.activeProfile else { return }
                        await connection.connect(to: profile)
                    }
            }
        }
        .overlay {
            if showsCrashReportingConsent {
                CrashReportingConsentView { enabled in
                    CrashReporting.setConsent(enabled: enabled)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showsCrashReportingConsent = false
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _, new in
            if new == .background || new == .inactive {
                torrentStore.pausePolling()
            } else if new == .active {
                torrentStore.resumePolling()
            }
        }
        // Stop sharing the live service with App Intents once the app drops the
        // connection; otherwise an intent keeps talking to a dead connection.
        .onChange(of: torrentStore.connection) { _, new in
            connection.connectionStateChanged(new)
        }
        .onDisappear { torrentStore.pausePolling() }
        .onAppear {
            if hasAppeared { torrentStore.resumePolling() }
            hasAppeared = true
            showsCrashReportingConsent = shouldOfferCrashReportingConsent
        }
        // Donate the server list to Spotlight once at launch. (Torrents are
        // donated by Get Torrents to avoid indexing on every poll.)
        .task { await SpotlightIndexer.indexServers(profileStore.profiles) }
    }

    /// Show the first-run splash only for a real, interactive, DSN-carrying
    /// build that has not answered yet. The answer is persisted by
    /// `CrashReporting.setConsent`, so this stays false afterwards.
    private var shouldOfferCrashReportingConsent: Bool {
        !disableOnboarding && !AppProcess.isXcodeAuxiliary && CrashReporting.isConfigured
            && CrashReporting.needsConsent
    }
}

// MARK: - First-run crash-reporting consent

/// The first-run splash. Explains the opt-in in one breath and lets the user
/// enable or decline. `onDecision` persists the answer and dismisses.
private struct CrashReportingConsentView: View {
    let onDecision: (Bool) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "ladybug.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Help improve TransmissionSwift")
                .font(.title2.weight(.semibold))
            Text("Send anonymous crash reports? \(CrashReporting.privacySummary)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Text("You can change this later in Settings.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            HStack(spacing: 12) {
                Button("Not Now") { onDecision(false) }
                    .accessibilityIdentifier("crashConsent.decline")
                Button("Enable Crash Reports") { onDecision(true) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("crashConsent.accept")
            }
            .padding(.top, 4)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .contentShape(Rectangle())
    }
}
