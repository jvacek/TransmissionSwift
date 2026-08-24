import AppKit
import Foundation
import Observation
import TransmissionCore
import os

private let logger = Logger(subsystem: "net.jvacek.TransmissionSwift", category: "FaviconStore")

/// LRU cache for tracking recently used hosts (max 200)
private final class LRUCache<Key: Hashable> {
    private var order: [Key] = []
    private var set: Set<Key> = []
    let capacity: Int

    init(capacity: Int) { self.capacity = capacity }

    func insert(_ key: Key) {
        if set.contains(key) {
            order.removeAll { $0 == key }
        } else if order.count >= capacity {
            let evicted = order.removeFirst()
            set.remove(evicted)
        }
        order.append(key)
        set.insert(key)
    }

    func contains(_ key: Key) -> Bool { set.contains(key) }

    func removeAll() {
        order.removeAll()
        set.removeAll()
    }

    var all: [Key] { order }
    var count: Int { order.count }
}

/// Owns the in-memory favicon images for the sidebar and orchestrates
/// non-blocking fetches/refreshes through `FaviconService`. The store is
/// `@MainActor` so UI updates land on the main thread; the actual network
/// work runs off-main inside the service actor.
@MainActor
@Observable
final class FaviconStore {
    private(set) var images: [String: NSImage] = [:]
    var enabled: Bool
    private let service: FaviconService
    private var knownHosts: LRUCache<String>
    private static let maxKnownHosts = 200
    private var isRefreshing = false
    private static let key = "fetchTrackerFavicons"

    init(cacheDirectory: URL? = nil) {
        let dir =
            cacheDirectory
            ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("net.jvacek.TransmissionSwift/Favicons"))
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Favicons")
        service = FaviconService(cacheDirectory: dir)
        knownHosts = LRUCache(capacity: Self.maxKnownHosts)
        enabled =
            UserDefaults.standard.object(forKey: Self.key) == nil
            ? true
            : UserDefaults.standard.bool(forKey: Self.key)
        logger.info("FaviconStore initialized (enabled: \(self.enabled))")
    }

    func setEnabled(_ newValue: Bool) {
        enabled = newValue
        UserDefaults.standard.set(newValue, forKey: Self.key)
        if !newValue {
            images = [:]
            knownHosts.removeAll()
            logger.info("Favicon fetching disabled, cleared cache")
        } else if !knownHosts.all.isEmpty {
            logger.info("Favicon fetching enabled, refreshing \(self.knownHosts.count) known hosts")
            Task { await refresh(hosts: knownHosts.all) }
        }
    }

    func image(for host: String) -> NSImage? { images[host] }

    /// Fetch favicons for the given tracker hosts. Already-cached hosts are
    /// skipped unless `forceRevalidate` is set (used on app launch to check
    /// for updates). Runs entirely off the main thread; images are published
    /// as they arrive.
    func refresh(hosts: [String], forceRevalidate: Bool = false) async {
        guard enabled else { return }
        guard !isRefreshing else { return }
        let hostsSet = Set(hosts)
        for host in hostsSet { knownHosts.insert(host) }
        let toFetch = forceRevalidate ? hostsSet : hostsSet.subtracting(images.keys)
        logger.info(
            "Favicon refresh: \(hosts.count) hosts requested, \(toFetch.count) to fetch (forceRevalidate: \(forceRevalidate))"
        )
        guard !toFetch.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let service = self.service
        await withTaskGroup(of: (String, Data?).self) { group in
            for host in toFetch {
                group.addTask { [service] in
                    let data = await service.icon(for: host, forceRevalidate: forceRevalidate)
                    return (host, data)
                }
            }
            for await (host, data) in group {
                if let data, let image = NSImage(data: data) {
                    images[host] = image
                    logger.info("Cached favicon for \(host, privacy: .public) (\(data.count) bytes)")
                } else {
                    logger.debug("No favicon data for \(host, privacy: .public)")
                }
            }
        }
    }

    func startupRefresh(hosts: [String]) async {
        logger.info("Startup favicon refresh for \(hosts.count) hosts: \(hosts, privacy: .public)")
        await refresh(hosts: hosts, forceRevalidate: true)
    }
}
