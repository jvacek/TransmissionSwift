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

    private let keychain = KeychainStore()
    @State private var hasAppeared = false
    @State private var connectedProfileID: ServerProfile.ID?
    @State private var showsCrashReportingConsent = false

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
                        await connectToProfile(profile)
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
            if case .disconnected = new { AppEnvironment.current?.clearConnection() }
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

    /// True when running as Xcode's test-host or preview process. The launch
    /// auto-connect reads the Keychain, and doing that from these freshly
    /// re-signed binaries triggers a keychain authorization prompt even though
    /// nothing user-initiated asked for the password.
    private var isXcodeAuxiliaryProcess: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    /// Show the first-run splash only for a real, interactive, DSN-carrying
    /// build that has not answered yet. The answer is persisted by
    /// `CrashReporting.setConsent`, so this stays false afterwards.
    private var shouldOfferCrashReportingConsent: Bool {
        !disableOnboarding && !isXcodeAuxiliaryProcess && CrashReporting.isConfigured
            && CrashReporting.needsConsent
    }

    @MainActor
    private func connectToProfile(_ profile: ServerProfile) async {
        // Skip the launch auto-connect under the test runner / previews — no
        // connection is needed there, and reading the Keychain prompts.
        if isXcodeAuxiliaryProcess { return }

        // Window was closed and reopened while already connected to this same
        // profile — onAppear's resumePolling() already restarted the stream.
        if case .connected = torrentStore.connection, connectedProfileID == profile.id { return }

        var credentials: Credentials?
        if let username = profile.username, !username.isEmpty {
            // Cancel the mock stream and show "waiting for keychain" before
            // the macOS dialog blocks — prevents the mock from racing back.
            torrentStore.beginKeychainWait()
            let profileID = profile.id
            let kc = keychain
            let password = await Task.detached(priority: .userInitiated) {
                (try? kc.password(for: profileID)) ?? ""
            }.value
            guard !Task.isCancelled else { return }
            credentials = Credentials(username: username, password: password)
        }
        guard let service = TransmissionServiceFactory.make(for: profile, credentials: credentials)
        else {
            torrentStore.setConnectionFailed(reason: "Invalid server URL")
            return
        }
        torrentStore.connect(service: service)
        AppEnvironment.current?.setConnected(service, for: profile)
        connectedProfileID = profile.id
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
