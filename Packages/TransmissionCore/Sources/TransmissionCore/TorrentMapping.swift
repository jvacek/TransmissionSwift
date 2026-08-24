import Foundation
import TransmissionRPC

/// Normalize a tracker host string into a bare hostname for favicon fetching
/// and display. The RPC returns `trackerStats[].host` as `host:port` (e.g.
/// "tracker.example.org:1337") while `trackers[].announce` is a full URL; both
/// should collapse to just the hostname so the favicon service hits the web
/// server on the standard port rather than the tracker's announce port.
private func trackerHostname(_ host: String) -> String {
    if let url = URL(string: host), url.host != nil {
        return url.host!
    }
    if let url = URL(string: "https://" + host), let hostname = url.host {
        return hostname
    }
    return host
}

extension Torrent {
    public init(wire: WireTorrent) {
        var status = Self.mapStatus(wireStatus: wire.status, error: wire.error, isFinished: wire.isFinished)

        let eta: TimeInterval? = wire.eta > 0 ? TimeInterval(wire.eta) : nil

        let priority: TorrentPriority
        switch wire.bandwidthPriority {
        case -1: priority = .low
        case 1: priority = .high
        default: priority = .normal
        }

        // Ceiling division: complete torrent with a short last piece → pieceCount, not pieceCount - 1.
        let havePieces =
            wire.pieceSize > 0
            ? Int((wire.haveValid + wire.pieceSize - 1) / wire.pieceSize)
            : 0

        let queuePosition: Int? = wire.queuePosition >= 0 ? wire.queuePosition : nil

        var errorMessage: String? =
            wire.error >= 2
            ? (wire.errorString.isEmpty ? "Error \(wire.error)" : wire.errorString)
            : nil

        let primaryTracker: String
        if let stub = wire.trackers?.first {
            // Prefer FQDN from announce URL over sitename (which may be a short name)
            primaryTracker = URL(string: stub.announce)?.host ?? stub.sitename ?? stub.announce
        } else {
            primaryTracker = ""
        }

        // Use rich trackerStats when present (inspector poll); fall back to lightweight stubs.
        let resolvedTrackers: [Tracker]
        if let stats = wire.trackerStats, let stubs = wire.trackers, !stubs.isEmpty {
            // Match stats to stubs by tier to get the real announce URL hostname.
            // Build a lookup: tier -> announce host from stubs.
            var tierToHost: [Int: String] = [:]
            for stub in stubs {
                if tierToHost[stub.tier] == nil,
                    let url = URL(string: stub.announce),
                    let host = url.host
                {
                    tierToHost[stub.tier] = host
                }
            }
            resolvedTrackers = stats.map { stat in
                // stat.host from Transmission RPC is `host:port` (e.g.
                // "tracker.example.org:1337"), not a full URL. Normalize it to
                // a bare hostname so the sidebar/favicon service don't connect
                // to the tracker's announce port.
                let normalized = trackerHostname(stat.host)
                let host = normalized.isEmpty ? (tierToHost[stat.tier] ?? stat.host) : normalized
                return Tracker(
                    tier: stat.tier,
                    host: host,
                    state: {
                        if stat.hasAnnounced && !stat.lastAnnounceSucceeded { return TrackerState.error }
                        if stat.lastAnnounceSucceeded || stat.announceState == 3 { return TrackerState.working }
                        return TrackerState.idle
                    }(),
                    statusMessage: {
                        if stat.hasAnnounced && !stat.lastAnnounceSucceeded {
                            return stat.lastAnnounceResult.isEmpty ? "Announce failed" : stat.lastAnnounceResult
                        } else if stat.lastAnnounceSucceeded || stat.announceState == 3 {
                            if stat.lastAnnounceTime > 0 {
                                let when = Date(timeIntervalSince1970: TimeInterval(stat.lastAnnounceTime))
                                    .formatted(.relative(presentation: .named))
                                return "Announced \(when)"
                            }
                            return "Working"
                        } else {
                            return stat.hasAnnounced ? "Waiting to announce" : "Not yet announced"
                        }
                    }(),
                    seedCount: stat.seederCount,
                    leechCount: stat.leecherCount,
                    downloadCount: stat.downloadCount
                )
            }
        } else if let stats = wire.trackerStats {
            // Stats present but no stubs - try to extract host from stat.host
            resolvedTrackers = stats.map { stat in
                let host = trackerHostname(stat.host)
                return Tracker(
                    tier: stat.tier,
                    host: host,
                    state: {
                        if stat.hasAnnounced && !stat.lastAnnounceSucceeded { return TrackerState.error }
                        if stat.lastAnnounceSucceeded || stat.announceState == 3 { return TrackerState.working }
                        return TrackerState.idle
                    }(),
                    statusMessage: {
                        if stat.hasAnnounced && !stat.lastAnnounceSucceeded {
                            return stat.lastAnnounceResult.isEmpty ? "Announce failed" : stat.lastAnnounceResult
                        } else if stat.lastAnnounceSucceeded || stat.announceState == 3 {
                            if stat.lastAnnounceTime > 0 {
                                let when = Date(timeIntervalSince1970: TimeInterval(stat.lastAnnounceTime))
                                    .formatted(.relative(presentation: .named))
                                return "Announced \(when)"
                            }
                            return "Working"
                        } else {
                            return stat.hasAnnounced ? "Waiting to announce" : "Not yet announced"
                        }
                    }(),
                    seedCount: stat.seederCount,
                    leechCount: stat.leecherCount,
                    downloadCount: stat.downloadCount
                )
            }
        } else {
            resolvedTrackers = (wire.trackers ?? []).map { stub in
                // Prefer FQDN from announce URL over sitename (which may be a short name like "flacsfor")
                let host = URL(string: stub.announce)?.host ?? stub.sitename ?? stub.announce
                return Tracker(
                    tier: stub.tier,
                    host: host,
                    state: .idle,
                    statusMessage: "",
                    seedCount: 0,
                    leechCount: 0,
                    downloadCount: 0
                )
            }
        }

        // Transmission only raises the torrent-level `error` for hard failures
        // (tracker rejection, local errors). A tracker that's merely unreachable
        // leaves `error == 0` and gets retried silently — so when every tracker
        // has announced and failed, treat the torrent itself as errored.
        let allTrackersFailed =
            !resolvedTrackers.isEmpty
            && resolvedTrackers.allSatisfy { $0.state == .error }

        if status == .downloading || status == .seeding, allTrackersFailed {
            status = .error
            if errorMessage == nil {
                let reasons = Set(resolvedTrackers.compactMap(\.statusMessage).filter { !$0.isEmpty })
                    .sorted()
                errorMessage =
                    reasons.isEmpty
                    ? "All trackers failed"
                    : "All trackers failed — \(reasons.joined(separator: " · "))"
            }
        }

        let resolvedFiles: [TorrentFile]
        if let wireFiles = wire.files, let wireStats = wire.fileStats,
            wireFiles.count == wireStats.count
        {
            resolvedFiles = zip(wireFiles, wireStats).enumerated().map { index, pair in
                TorrentFile(file: pair.0, stat: pair.1, index: index)
            }
        } else {
            resolvedFiles = []
        }

        let resolvedPeers: [Peer] = (wire.peers ?? []).map { Peer(wire: $0) }

        self.init(
            id: wire.id,
            name: wire.name,
            hash: wire.hashString,
            size: wire.totalSize,
            status: status,
            progress: wire.percentDone,
            downloadSpeed: wire.rateDownload,
            uploadSpeed: wire.rateUpload,
            connectedPeerCount: wire.peersConnected,
            availablePeerCount: wire.peersFrom.total,
            seedCount: 0,
            eta: eta,
            ratio: wire.uploadRatio,
            primaryTracker: primaryTracker,
            downloadFolder: wire.downloadDir,
            addedAt: Date(timeIntervalSince1970: TimeInterval(wire.addedDate)),
            labels: wire.labels ?? [],
            priority: priority,
            pieces: wire.pieceCount,
            pieceSize: wire.pieceSize,
            havePieces: havePieces,
            queuePosition: queuePosition,
            errorMessage: errorMessage,
            options: TorrentOptions(),
            files: resolvedFiles,
            peers: resolvedPeers,
            trackers: resolvedTrackers,
            comment: wire.comment.flatMap { $0.isEmpty ? nil : $0 },
            creator: wire.creator.flatMap { $0.isEmpty ? nil : $0 },
            createdAt: wire.dateCreated.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            isPrivate: wire.isPrivate ?? false,
            downloadedEver: wire.downloadedEver ?? 0,
            uploadedEver: wire.uploadedEver ?? 0,
            lastActivityAt: {
                guard let seconds = wire.activityDate, seconds > 0 else { return nil }
                return Date(timeIntervalSince1970: TimeInterval(seconds))
            }(),
            magnetLink: wire.magnetLink.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    // Internal so TorrentMappingTests can verify the logic table directly.
    static func mapStatus(wireStatus: Int, error: Int, isFinished: Bool) -> TorrentStatus {
        if error >= 2 { return .error }
        if isFinished { return .completed }
        switch wireStatus {
        case 0: return .paused
        case 1, 3, 5: return .queued
        case 2: return .checking
        case 4: return .downloading
        case 6: return .seeding
        default: return .paused
        }
    }
}

extension TorrentFile {
    init(file: WireFile, stat: WireFileStat, index: Int) {
        let priority: TorrentPriority
        switch stat.priority {
        case -1: priority = .low
        case 1: priority = .high
        default: priority = .normal
        }
        let progress = file.length > 0 ? Double(stat.bytesCompleted) / Double(file.length) : 0
        self.init(
            id: index,
            name: file.name,
            size: file.length,
            progress: progress,
            priority: priority,
            wanted: stat.wanted
        )
    }
}

extension Peer {
    init(wire: WirePeer) {
        self.init(
            ipAddress: wire.address,
            client: wire.clientName,
            countryCode: nil,
            flags: wire.flagStr,
            progress: wire.progress,
            downloadSpeed: wire.rateToClient,
            uploadSpeed: wire.rateToPeer
        )
    }
}

extension Tracker {
    init(stat: WireTrackerStat) {
        let state: TrackerState
        let statusMessage: String

        if stat.hasAnnounced && !stat.lastAnnounceSucceeded {
            state = .error
            statusMessage = stat.lastAnnounceResult.isEmpty ? "Announce failed" : stat.lastAnnounceResult
        } else if stat.lastAnnounceSucceeded || stat.announceState == 3 {
            state = .working
            if stat.lastAnnounceTime > 0 {
                let when = Date(timeIntervalSince1970: TimeInterval(stat.lastAnnounceTime))
                    .formatted(.relative(presentation: .named))
                statusMessage = "Announced \(when)"
            } else {
                statusMessage = "Working"
            }
        } else {
            state = .idle
            statusMessage = stat.hasAnnounced ? "Waiting to announce" : "Not yet announced"
        }

        // stat.host from Transmission RPC is `host:port` (e.g.,
        // "tracker.example.org:1337"), not a full URL. Normalize it to a bare
        // hostname for favicon fetching and display.
        let hostname = trackerHostname(stat.host)

        self.init(
            tier: stat.tier,
            host: hostname,
            state: state,
            statusMessage: statusMessage,
            seedCount: stat.seederCount,
            leechCount: stat.leecherCount,
            downloadCount: stat.downloadCount
        )
    }
}
