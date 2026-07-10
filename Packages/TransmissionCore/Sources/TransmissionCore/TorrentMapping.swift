import Foundation
import TransmissionRPC

extension Torrent {
    public init(wire: WireTorrent) {
        let status = Self.mapStatus(wireStatus: wire.status, error: wire.error, isFinished: wire.isFinished)

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

        let errorMessage: String? =
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
                // Use stat.host if it's a valid FQDN; otherwise fall back to stub's announce host.
                // stat.host from Transmission RPC is typically the full announce URL (e.g., "http://tracker.example.com:80/announce").
                // Extract hostname from URL if possible.
                let host: String
                if let url = URL(string: stat.host), let urlHost = url.host {
                    host = urlHost
                } else if stat.host.contains(".") && !stat.host.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":" }) {
                    // Fallback: if it looks like an FQDN (has dots, not just numbers/dots/colons), use as-is
                    host = stat.host
                } else {
                    host = tierToHost[stat.tier] ?? stat.host
                }
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
                let host: String
                if let url = URL(string: stat.host), let h = url.host {
                    host = h
                } else {
                    host = stat.host
                }
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
            label: wire.labels?.first,
            priority: priority,
            pieces: wire.pieceCount,
            pieceSize: wire.pieceSize,
            havePieces: havePieces,
            queuePosition: queuePosition,
            errorMessage: errorMessage,
            options: TorrentOptions(),
            files: resolvedFiles,
            peers: resolvedPeers,
            trackers: resolvedTrackers
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

        // stat.host contains the full announce URL (e.g., "http://tracker.example.com:80/announce").
        // Extract just the hostname for favicon fetching and display.
        let hostname: String
        if let url = URL(string: stat.host), let host = url.host {
            hostname = host
        } else {
            hostname = stat.host
        }

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
