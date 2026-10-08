import TransmissionCore

/// One row context-menu entry: what it is, whether it is enabled, and (for
/// priority entries) whether it is the checked one. Kept free of AppKit so the
/// enablement rules can be tested without an `NSMenu`.
nonisolated struct TorrentRowMenuItem: Equatable {
    enum Kind: Equatable {
        case resume
        case pause
        case priority(TorrentPriority)
        case separator
        case verify
        case reannounce
        case mapping(OpenMapping)
        case editLabels
        case setLocation
        case rename
        case remove
        case removeAndDeleteData
    }

    let kind: Kind
    let isEnabled: Bool
    /// Priority entries only: the affected torrents all share this priority.
    let isChecked: Bool

    init(_ kind: Kind, isEnabled: Bool = true, isChecked: Bool = false) {
        self.kind = kind
        self.isEnabled = isEnabled
        self.isChecked = isChecked
    }
}

/// Builds the row context-menu spec. The `Coordinator` maps each entry to an
/// `NSMenuItem`; every capability rule lives here, so the enablement matrix is
/// testable without a window.
nonisolated enum TorrentRowMenu {
    static func items(
        ids: [Torrent.ID],
        priorities: [TorrentPriority],
        actionsEnabled: Bool,
        labelsSupported: Bool,
        mappings: [OpenMapping]
    ) -> [TorrentRowMenuItem] {
        let canAct = actionsEnabled && !ids.isEmpty
        let single = ids.count == 1
        // The checked priority: only when every affected torrent shares one.
        let uniformPriority = Set(priorities).count == 1 ? priorities.first : nil

        var items: [TorrentRowMenuItem] = []
        items.append(TorrentRowMenuItem(.resume, isEnabled: canAct))
        items.append(TorrentRowMenuItem(.pause, isEnabled: canAct))
        for priority in TorrentPriority.allCases {
            items.append(
                TorrentRowMenuItem(
                    .priority(priority),
                    isEnabled: canAct,
                    isChecked: priority == uniformPriority))
        }
        items.append(TorrentRowMenuItem(.separator))
        items.append(TorrentRowMenuItem(.verify, isEnabled: canAct))
        items.append(TorrentRowMenuItem(.reannounce, isEnabled: canAct))
        items.append(TorrentRowMenuItem(.separator))
        if !mappings.isEmpty {
            for mapping in mappings {
                // "Open with…" opens one torrent's path, so it needs a single id.
                items.append(
                    TorrentRowMenuItem(.mapping(mapping), isEnabled: actionsEnabled && single))
            }
            items.append(TorrentRowMenuItem(.separator))
        }
        items.append(TorrentRowMenuItem(.editLabels, isEnabled: canAct && labelsSupported))
        items.append(TorrentRowMenuItem(.setLocation, isEnabled: canAct))
        items.append(TorrentRowMenuItem(.rename, isEnabled: canAct && single))
        items.append(TorrentRowMenuItem(.separator))
        items.append(TorrentRowMenuItem(.remove, isEnabled: canAct))
        items.append(TorrentRowMenuItem(.removeAndDeleteData, isEnabled: canAct))
        return items
    }
}
