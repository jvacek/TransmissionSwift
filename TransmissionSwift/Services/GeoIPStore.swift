import Foundation
import Observation
import TransmissionCore
import os

private let logger = Logger(subsystem: "net.jvacek.TransmissionSwift", category: "GeoIPStore")

/// Resolves peer IPs to ISO-3166 country codes for the peer table's flag
/// column. Owns the DB-IP-backed `GeoIPService` and caches results per IP so
/// repeated peer polls don't re-query. Mirrors `FaviconStore`.
@MainActor
@Observable
final class GeoIPStore {
    /// IP → country code; empty string means "resolved, no country".
    private(set) var codes: [String: String] = [:]
    var enabled: Bool
    var refreshFrequency: GeoIPRefreshFrequency

    private let service: GeoIPService

    init(cacheDirectory: URL? = nil) {
        let directory =
            cacheDirectory
            ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("net.jvacek.TransmissionSwift/GeoIP"))
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("GeoIP")
        let storedFrequency =
            UserDefaults.standard.string(forKey: PreferenceKeys.geoIPRefreshFrequency)
            .flatMap(GeoIPRefreshFrequency.init(rawValue:)) ?? .monthly
        refreshFrequency = storedFrequency
        var configuration = GeoIPServiceConfiguration()
        configuration.refreshFrequency = storedFrequency
        service = GeoIPService(cacheDirectory: directory, configuration: configuration)
        enabled =
            UserDefaults.standard.object(forKey: PreferenceKeys.showPeerCountryFlags) == nil
            ? true
            : UserDefaults.standard.bool(forKey: PreferenceKeys.showPeerCountryFlags)
    }

    func setEnabled(_ newValue: Bool) {
        enabled = newValue
        UserDefaults.standard.set(newValue, forKey: PreferenceKeys.showPeerCountryFlags)
        if !newValue {
            codes = [:]
            logger.info("Peer country flags disabled, cleared resolved codes")
        }
    }

    func setRefreshFrequency(_ newValue: GeoIPRefreshFrequency) {
        refreshFrequency = newValue
        UserDefaults.standard.set(newValue.rawValue, forKey: PreferenceKeys.geoIPRefreshFrequency)
        Task { await service.setRefreshFrequency(newValue) }
    }

    /// Cached country code for an IP, or nil when unknown or not yet resolved.
    func code(for ip: String) -> String? {
        codes[ip].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Resolve any peers not seen before. Safe to call every poll: known IPs
    /// are skipped and the underlying database is fetched at most monthly.
    func resolve(_ peers: [Peer]) async {
        guard enabled else { return }
        let pending = Set(peers.map(\.ipAddress)).filter { !$0.isEmpty && codes[$0] == nil }
        guard !pending.isEmpty else { return }
        for ip in pending {
            codes[ip] = await service.countryCode(forIPv4Address: ip) ?? ""
        }
    }
}
