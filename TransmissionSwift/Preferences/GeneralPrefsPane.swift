// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import TransmissionCore

struct GeneralPrefsPane: View {
    @AppStorage(PreferenceKeys.interfaceLanguage) private var interfaceLanguage = InterfaceLanguage.system
    @AppStorage(PreferenceKeys.showAddDialogBeforeAdding) private var showAddDialog = true
    @AppStorage(PreferenceKeys.deleteTorrentFileAfterAdding) private var deleteTorrentFileAfterAdding = false
    @AppStorage(PreferenceKeys.startMinimized) private var startMinimized = false
    @AppStorage(PreferenceKeys.badgeAppIcon) private var badgeAppIcon = false
    @AppStorage(PreferenceKeys.confirmRemove) private var confirmRemove = true
    @AppStorage(PreferenceKeys.showDonateButton) private var showDonateButton = true
    @AppStorage(PreferenceKeys.showBugReportButton) private var showBugReportButton = true
    @AppStorage(PreferenceKeys.sendCrashReports) private var sendCrashReports = false
    @AppStorage(PreferenceKeys.pollingIntervalSeconds) private var pollingInterval: Double = PollingIntervals
        .defaultRefresh
    @AppStorage(PreferenceKeys.incrementalPollingIntervalSeconds) private var incrementalPollingInterval: Double =
        PollingIntervals.defaultIncremental
    @AppStorage(PreferenceKeys.freeSpaceIntervalSeconds) private var freeSpaceInterval: Double = PollingIntervals
        .defaultFreeSpace
    @AppStorage(PreferenceKeys.fetchTrackerFavicons) private var fetchFavicons = true
    @AppStorage(PreferenceKeys.showPeerCountryFlags) private var showPeerFlags = true
    @AppStorage(PreferenceKeys.geoIPRefreshFrequency) private var geoIPRefresh = GeoIPRefreshFrequency.monthly
    @Environment(FaviconStore.self) private var favicons
    @Environment(GeoIPStore.self) private var geoip

    var body: some View {
        Form {
            Section {
                Toggle(L10n.text("Show dialog before adding a torrent"), isOn: $showAddDialog)
                Toggle(
                    L10n.text("Delete .torrent file after adding by default"),
                    isOn: $deleteTorrentFileAfterAdding)
            } header: {
                Text(L10n.text("Downloads"))
            } footer: {
                Text(
                    L10n.text(
                        "The Add Torrent dialog starts with this option checked; you can turn it off for a single add. Adds that skip the dialog — drag & drop and “Open With” — follow this default directly. Magnet links have no file to delete."
                    )
                )
            }
            Section {
                secondsRow(
                    L10n.text("Refresh interval"), value: $pollingInterval,
                    help: L10n.format(
                        "How often the whole list refreshes, %@",
                        rangeText(PollingIntervals.refresh)))
                secondsRow(
                    L10n.text("Incremental refresh interval"), value: $incrementalPollingInterval,
                    help: L10n.format(
                        "How often changed torrents refresh, %@ and never above the refresh interval",
                        rangeText(PollingIntervals.incremental)))
                secondsRow(
                    L10n.text("Free space interval"), value: $freeSpaceInterval,
                    help: L10n.format(
                        "How often free disk space is re-read, %@",
                        rangeText(PollingIntervals.freeSpace)))
            } header: {
                Text(L10n.text("Connection"))
            } footer: {
                Text(
                    L10n.text(
                        "The full list refreshes every “Refresh interval” seconds. Changed torrents, and the inspector, refresh at the incremental interval in between, which is capped at 45 seconds and at the refresh interval. Values are whole seconds."
                    )
                )
            }
            Section(L10n.text("Sidebar")) {
                Toggle(L10n.text("Fetch tracker favicons"), isOn: $fetchFavicons)
                    .onChange(of: fetchFavicons) { _, newValue in
                        favicons.setEnabled(newValue)
                    }
            }
            Section {
                Toggle(L10n.text("Show country flags for peers"), isOn: $showPeerFlags)
                    .onChange(of: showPeerFlags) { _, newValue in
                        geoip.setEnabled(newValue)
                    }
                Picker(L10n.text("Check for updates"), selection: $geoIPRefresh) {
                    ForEach(GeoIPRefreshFrequency.allCases, id: \.self) { frequency in
                        Text(frequency.displayLabel).tag(frequency)
                    }
                }
                .onChange(of: geoIPRefresh) { _, newValue in
                    geoip.setRefreshFrequency(newValue)
                }
                .disabled(!showPeerFlags)
            } header: {
                Text(L10n.text("Peers"))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        L10n.text(
                            "Downloads a public IP-to-country database (about 4.5 MB). DB-IP releases it monthly, so daily or weekly checks usually just confirm it's current. Peer IP addresses never leave your Mac."
                        )
                    )
                    Link(
                        L10n.text("IP Geolocation by DB-IP"),
                        destination: URL(string: "https://db-ip.com")!)
                }
                .font(.caption)
            }
            Section(L10n.text("Application")) {
                Picker(L10n.text("Language"), selection: $interfaceLanguage) {
                    ForEach(InterfaceLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                Toggle(L10n.text("Badge app icon with active count"), isOn: $badgeAppIcon)
                Toggle(L10n.text("Start minimized"), isOn: $startMinimized)
                Toggle(L10n.text("Confirm before removing"), isOn: $confirmRemove)
            }
            Section(L10n.text("Links on status bar")) {
                Toggle(L10n.text("Show donate button"), isOn: $showDonateButton)
                Toggle(L10n.text("Show bug report button"), isOn: $showBugReportButton)
            }
            Section {
                Toggle(L10n.text("Send anonymous crash reports"), isOn: $sendCrashReports)
                    .onChange(of: sendCrashReports) { _, newValue in
                        CrashReporting.setConsent(enabled: newValue)
                    }
            } header: {
                Text(L10n.text("Diagnostics"))
            } footer: {
                Text(
                    L10n.format(
                        "Crash reports help fix bugs. %@ Off by default.",
                        CrashReporting.privacySummary))
            }
        }
        .formStyle(.grouped)
        .onAppear { normalizeIntervals() }
        .onChange(of: pollingInterval) { _, _ in intervalEdited() }
        .onChange(of: incrementalPollingInterval) { _, _ in intervalEdited() }
        .onChange(of: freeSpaceInterval) { _, _ in intervalEdited() }
    }

    /// Every edit, valid or clamped, has to reach a loop that may already be
    /// asleep: a plain 15 -> 20 change is exactly the case that must cut the
    /// current sleep short, so this can't depend on a clamp having fired.
    private func intervalEdited() {
        normalizeIntervals()
        NotificationCenter.default.post(name: PollingIntervals.changed, object: nil)
    }

    /// Keep every field inside the range the service honors, including the
    /// incremental interval's dependence on the refresh interval. Runs after
    /// each edit so no invalid value is ever stored.
    private func normalizeIntervals() {
        let refresh = PollingIntervals.normalized(pollingInterval, to: PollingIntervals.refresh)
        if refresh != pollingInterval {
            pollingInterval = refresh
        }

        let incremental = PollingIntervals.clampedIncremental(
            incrementalPollingInterval, refresh: refresh)
        if incremental != incrementalPollingInterval {
            incrementalPollingInterval = incremental
        }

        let freeSpace = PollingIntervals.normalized(freeSpaceInterval, to: PollingIntervals.freeSpace)
        if freeSpace != freeSpaceInterval {
            freeSpaceInterval = freeSpace
        }
    }

    /// A whole-seconds field with a fixed unit slot, so every interval row has
    /// the same geometry and the numbers line up with each other and with the
    /// switches in the sections above. Laid out by hand because a
    /// `LabeledContent` sizes its content column instead of reaching the row's
    /// trailing edge, which left the fields short of the switches.
    private func secondsRow(_ title: String, value: Binding<Double>, help: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
            Spacer(minLength: 24)
            TextField("", value: value, format: .number.precision(.fractionLength(0)))
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 60)
                .accessibilityLabel(title)
            Text(value.wrappedValue == 1 ? L10n.text("second") : L10n.text("seconds"))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
        }
        .help(help)
    }

    private func rangeText(_ range: ClosedRange<Double>) -> String {
        L10n.format(
            "between %lld and %lld seconds",
            Int64(range.lowerBound), Int64(range.upperBound))
    }
}

#if DEBUG
#Preview("General") {
    GeneralPrefsPane()
        .environment(FaviconStore())
        .environment(GeoIPStore())
        .frame(width: 480, height: 1080)
}
#endif
