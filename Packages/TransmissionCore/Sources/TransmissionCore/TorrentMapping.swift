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
            primaryTracker = stub.sitename ?? URL(string: stub.announce)?.host ?? stub.announce
        } else {
            primaryTracker = ""
        }

        // Use rich trackerStats when present (inspector poll); fall back to lightweight stubs.
        let resolvedTrackers: [Tracker]
        if let stats = wire.trackerStats {
            resolvedTrackers = stats.map { Tracker(stat: $0) }
        } else {
            resolvedTrackers = (wire.trackers ?? []).map { stub in
                let host = stub.sitename ?? URL(string: stub.announce)?.host ?? stub.announce
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

        self.init(
            tier: stat.tier,
            host: stat.host,
            state: state,
            statusMessage: statusMessage,
            seedCount: stat.seederCount,
            leechCount: stat.leecherCount,
            downloadCount: stat.downloadCount
        )
    }
}
