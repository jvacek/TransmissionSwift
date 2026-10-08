import AppKit
import TransmissionCore

/// Equatable display value for one table cell, rendered natively (no
/// NSHostingView). The cell skips re-rendering when the value is unchanged, so
/// the per-second poll only touches cells whose content actually moved.
struct TorrentCellContent: Equatable {
    enum Shape: Equatable {
        case text  // single label
        case dotAndText  // colored dot + label (name, status)
        case progress  // bar + percent label
        case twoPart  // value + unit (speed)
        case symbolAndText  // SF symbol + label (priority)
        case pill  // label on a rounded background
        case pills  // multiple pill labels (torrent tags)
    }

    var shape: Shape
    var text: String
    var font: NSFont
    var color: NSColor
    var alignment: NSTextAlignment
    var toolTip: String?
    var accessibilityLabel: String
    var dotColor: NSColor?
    var progressValue: Double?
    var progressTint: NSColor?
    var percentText: String?
    var secondaryText: String?
    var secondaryFont: NSFont?
    var secondaryColor: NSColor?
    var symbolName: String?
    var symbolColor: NSColor?
    /// Pill texts for the `.pills` shape. `text` stays populated (first label)
    /// so existing consumers never see an empty cell.
    var pillTexts: [String]?
    /// Finder-style tag dots rendered after the name text (one per tag; grey
    /// when the tag has no colour), for the `.dotAndText` shape.
    var trailingDotColors: [NSColor]?
    /// Per-pill solid backgrounds / foregrounds for the `.pills` shape, aligned
    /// with `pillTexts`. Absent = the default grey pill styling.
    var pillBackgroundColors: [NSColor]?
    var pillForegroundColors: [NSColor]?
}

// MARK: - Display-value builder

extension TorrentCellContent {
    private static let bodyFont = NSFont.systemFont(ofSize: 13)
    private static let monoDigitFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    private static let captionFont = NSFont.systemFont(ofSize: 11)
    private static let captionMonoFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let caption2Font = NSFont.systemFont(ofSize: 10)
    private static let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    /// Builds the display value for `column` of `row`, folding the former
    /// `view(for:)` + `axLabel(for:)` into one place so they can't diverge.
    /// `tagColors` feeds the Finder-style tag dots and coloured label pills;
    /// it is external to the torrent (a local preference), so it is passed in
    /// rather than folded into `TorrentRowDisplay`.
    static func make(
        for column: TransmissionCore.TableColumn,
        row: TorrentRowDisplay,
        downloadDirectoryBase: String?,
        tagColors: [String: TagColor] = [:]
    ) -> TorrentCellContent {
        switch column {
        case .name:
            // Finder-style tag dots: one per tag, in the tag's colour when one
            // is assigned and grey otherwise — so multiple tags read as
            // multiple dots even before any colour is set.
            let tagDots = row.torrent.labels.map {
                tagColors[$0]?.nsColor ?? NSColor.tertiaryLabelColor
            }
            return TorrentCellContent(
                shape: .dotAndText,
                text: row.torrent.name,
                font: bodyFont,
                color: .labelColor,
                alignment: .left,
                toolTip: nil,
                accessibilityLabel: row.torrent.name,
                dotColor: row.torrent.status.nsDisplayColor,
                trailingDotColors: tagDots)
        case .size:
            let text = ColumnFormatters.humanizedSize(row.torrent.size)
            return TorrentCellContent(
                shape: .text,
                text: text,
                font: monoDigitFont,
                color: .secondaryLabelColor,
                alignment: .right,
                toolTip: nil,
                accessibilityLabel: text)
        case .progress:
            let percent = "\(Int((row.torrent.progress * 100).rounded()))%"
            return TorrentCellContent(
                shape: .progress,
                text: "",
                font: bodyFont,
                color: .labelColor,
                alignment: .left,
                toolTip: nil,
                accessibilityLabel: "\(Int((row.torrent.progress * 100).rounded())) percent",
                progressValue: row.torrent.progress,
                progressTint: row.torrent.status.nsDisplayColor,
                percentText: percent,
                secondaryFont: monoDigitFont,
                secondaryColor: .secondaryLabelColor)
        case .downloadSpeed:
            return speedContent(row.torrent.downloadSpeed, color: .systemBlue)
        case .uploadSpeed:
            return speedContent(row.torrent.uploadSpeed, color: .systemGreen)
        case .eta:
            let text = ColumnFormatters.humanizedETA(row.torrent.eta, status: row.torrent.status)
            return TorrentCellContent(
                shape: .text,
                text: text,
                font: monoDigitFont,
                color: etaColor(row.torrent.status),
                alignment: .right,
                toolTip: nil,
                accessibilityLabel: text)
        case .ratio:
            let (text, color) = ratioContent(row.torrent.ratio)
            return TorrentCellContent(
                shape: .text,
                text: text,
                font: monoDigitFont,
                color: color,
                alignment: .right,
                toolTip: nil,
                accessibilityLabel: text)
        case .addedAt:
            let text = ColumnFormatters.relativeDate(row.torrent.addedAt)
            return TorrentCellContent(
                shape: .text,
                text: text,
                font: monoDigitFont,
                color: .secondaryLabelColor,
                alignment: .right,
                toolTip: row.torrent.addedAt.formatted(date: .abbreviated, time: .complete),
                accessibilityLabel: row.torrent.addedAt.formatted(date: .abbreviated, time: .shortened))
        case .completedAt:
            return optionalDateContent(row.torrent.completedAt)
        case .startedAt:
            return optionalDateContent(row.torrent.startedAt)
        case .lastActivityAt:
            return optionalDateContent(row.torrent.lastActivityAt)
        case .primaryTracker:
            if row.torrent.primaryTracker.isEmpty {
                return TorrentCellContent(
                    shape: .text,
                    text: "\u{2014}",
                    font: bodyFont,
                    color: .tertiaryLabelColor,
                    alignment: .left,
                    toolTip: nil,
                    accessibilityLabel: "no tracker")
            }
            return TorrentCellContent(
                shape: .text,
                text: row.torrent.primaryTracker,
                font: captionMonoFont,
                color: .secondaryLabelColor,
                alignment: .left,
                toolTip: nil,
                accessibilityLabel: row.torrent.primaryTracker)
        case .connectedPeers:
            let text = "\(row.torrent.connectedPeerCount)/\(row.torrent.availablePeerCount)"
            return TorrentCellContent(
                shape: .text,
                text: text,
                font: monoDigitFont,
                color: .secondaryLabelColor,
                alignment: .right,
                toolTip: nil,
                accessibilityLabel: "\(row.torrent.connectedPeerCount) of \(row.torrent.availablePeerCount) peers")
        case .availablePeers:
            let text = row.torrent.availablePeerCount > 0 ? "\(row.torrent.availablePeerCount)" : "\u{2014}"
            return TorrentCellContent(
                shape: .text,
                text: text,
                font: monoDigitFont,
                color: row.torrent.availablePeerCount > 0 ? .secondaryLabelColor : .tertiaryLabelColor,
                alignment: .right,
                toolTip: nil,
                accessibilityLabel: "\(row.torrent.availablePeerCount) available")
        case .seeds:
            let text = row.torrent.seedCount > 0 ? "\(row.torrent.seedCount)" : "\u{2014}"
            return TorrentCellContent(
                shape: .text,
                text: text,
                font: monoDigitFont,
                color: row.torrent.seedCount > 0 ? .secondaryLabelColor : .tertiaryLabelColor,
                alignment: .right,
                toolTip: nil,
                accessibilityLabel: "\(row.torrent.seedCount) seeds")
        case .status:
            let (color, text) = statusContent(row.torrent.status)
            return TorrentCellContent(
                shape: .dotAndText,
                text: text,
                font: bodyFont,
                color: .secondaryLabelColor,
                alignment: .left,
                toolTip: nil,
                accessibilityLabel: text,
                dotColor: color)
        case .label:
            let labels = row.torrent.labels.filter { !$0.isEmpty }
            if !labels.isEmpty {
                // Uncoloured tags get the shared "neutral pill" fill — a light
                // translucent tint of the label colour, not `quaternaryLabelColor`
                // at a flat alpha (which is actually black/white at 40-50% and
                // renders far too dark with poor text contrast).
                let backgrounds = labels.map { label in
                    tagColors[label].map(\.nsColor) ?? NSColor.labelColor.withAlphaComponent(0.06)
                }
                let foregrounds = labels.map { label in
                    tagColors[label].map(\.nsPillForeground) ?? .labelColor
                }
                return TorrentCellContent(
                    shape: .pills,
                    text: labels[0],
                    font: bodyFont,
                    color: .labelColor,
                    alignment: .left,
                    toolTip: nil,
                    accessibilityLabel: labels.joined(separator: ", "),
                    pillTexts: labels,
                    pillBackgroundColors: backgrounds,
                    pillForegroundColors: foregrounds)
            }
            return TorrentCellContent(
                shape: .text,
                text: "\u{2014}",
                font: bodyFont,
                color: .tertiaryLabelColor,
                alignment: .left,
                toolTip: nil,
                accessibilityLabel: "no label")
        case .priority:
            let priority = row.torrent.priority
            return TorrentCellContent(
                shape: .symbolAndText,
                text: priority.displayLabel,
                font: captionFont,
                color: .secondaryLabelColor,
                alignment: .left,
                toolTip: priority.displayLabel,
                accessibilityLabel: priorityAXLabel(priority),
                symbolName: priority.systemImage,
                symbolColor: priority.nsDisplayColor)
        case .queuePosition:
            if let position = row.torrent.queuePosition {
                return TorrentCellContent(
                    shape: .text,
                    text: "#\(position)",
                    font: monoDigitFont,
                    color: .systemOrange,
                    alignment: .right,
                    toolTip: nil,
                    accessibilityLabel: ColumnFormatters.queuePosition(row.torrent.queuePosition))
            }
            return TorrentCellContent(
                shape: .text,
                text: "\u{2014}",
                font: monoDigitFont,
                color: .tertiaryLabelColor,
                alignment: .right,
                toolTip: nil,
                accessibilityLabel: ColumnFormatters.queuePosition(row.torrent.queuePosition))
        case .errorMessage:
            if let error = row.torrent.errorMessage, !error.isEmpty {
                return TorrentCellContent(
                    shape: .text,
                    text: error,
                    font: bodyFont,
                    color: .systemRed,
                    alignment: .left,
                    toolTip: error,
                    accessibilityLabel: error)
            }
            return TorrentCellContent(
                shape: .text,
                text: "\u{2014}",
                font: bodyFont,
                color: .tertiaryLabelColor,
                alignment: .left,
                toolTip: nil,
                accessibilityLabel: "no error")
        case .pieces:
            let text = ColumnFormatters.piecesText(have: row.torrent.havePieces, total: row.torrent.pieces)
            return TorrentCellContent(
                shape: .text,
                text: text,
                font: monoDigitFont,
                color: .secondaryLabelColor,
                alignment: .right,
                toolTip: nil,
                accessibilityLabel: text)
        case .downloadFolder:
            let display = ColumnFormatters.truncatedPath(
                row.torrent.downloadFolder, relativeTo: downloadDirectoryBase)
            return TorrentCellContent(
                shape: .text,
                text: display,
                font: captionMonoFont,
                color: .secondaryLabelColor,
                alignment: .left,
                toolTip: row.torrent.downloadFolder,
                accessibilityLabel: row.torrent.downloadFolder)
        case .hash:
            return TorrentCellContent(
                shape: .text,
                text: row.torrent.hash,
                font: monoFont,
                color: .secondaryLabelColor,
                alignment: .left,
                toolTip: row.torrent.hash,
                accessibilityLabel: row.torrent.hash)
        case .downloadedEver:
            return totalContent(row.torrent.downloadedEver, label: "downloaded")
        case .uploadedEver:
            return totalContent(row.torrent.uploadedEver, label: "uploaded")
        case .leftUntilDone:
            let text = ColumnFormatters.humanizedSize(row.torrent.leftUntilDone)
            return TorrentCellContent(
                shape: .text,
                text: text,
                font: monoDigitFont,
                color: .secondaryLabelColor,
                alignment: .right,
                toolTip: nil,
                accessibilityLabel: "\(text) remaining")
        case .sizeWhenDone:
            let text = ColumnFormatters.humanizedSize(row.torrent.sizeWhenDone)
            return TorrentCellContent(
                shape: .text,
                text: text,
                font: monoDigitFont,
                color: .secondaryLabelColor,
                alignment: .right,
                toolTip: nil,
                accessibilityLabel: "\(text) when done")
        case .secondsDownloading:
            return durationContent(row.torrent.secondsDownloading, label: "downloading")
        case .secondsSeeding:
            return durationContent(row.torrent.secondsSeeding, label: "seeding")
        case .downloadLimit:
            return limitContent(
                limited: row.torrent.options.downloadLimited,
                text: row.torrent.options.downloadLimited
                    ? ColumnFormatters.humanizedSpeed(Int64(row.torrent.options.downloadLimitKBps) * 1024) : nil,
                label: "download limit")
        case .uploadLimit:
            return limitContent(
                limited: row.torrent.options.uploadLimited,
                text: row.torrent.options.uploadLimited
                    ? ColumnFormatters.humanizedSpeed(Int64(row.torrent.options.uploadLimitKBps) * 1024) : nil,
                label: "upload limit")
        case .seedRatioLimit:
            return limitContent(
                limited: row.torrent.options.seedRatioLimited,
                text: row.torrent.options.seedRatioLimited
                    ? ColumnFormatters.ratio(row.torrent.options.seedRatioLimit) : nil,
                label: "ratio limit")
        case .seedIdleLimit:
            return limitContent(
                limited: row.torrent.options.seedIdleLimited,
                text: row.torrent.options.seedIdleLimited
                    ? "\(row.torrent.options.seedIdleMinutes)m" : nil,
                label: "idle limit")
        case .peerLimit:
            let text = "\(row.torrent.options.peerLimit)"
            return TorrentCellContent(
                shape: .text,
                text: text,
                font: monoDigitFont,
                color: .secondaryLabelColor,
                alignment: .right,
                toolTip: nil,
                accessibilityLabel: "\(text) peers")
        }
    }

    private static func optionalDateContent(_ date: Date?) -> TorrentCellContent {
        guard let date else {
            return TorrentCellContent(
                shape: .text,
                text: "\u{2014}",
                font: monoDigitFont,
                color: .tertiaryLabelColor,
                alignment: .right,
                toolTip: nil,
                accessibilityLabel: "never")
        }
        let text = ColumnFormatters.relativeDate(date)
        return TorrentCellContent(
            shape: .text,
            text: text,
            font: monoDigitFont,
            color: .secondaryLabelColor,
            alignment: .right,
            toolTip: date.formatted(date: .abbreviated, time: .complete),
            accessibilityLabel: date.formatted(date: .abbreviated, time: .shortened))
    }

    private static func totalContent(_ bytes: Int64, label: String) -> TorrentCellContent {
        let text = ColumnFormatters.humanizedSize(bytes)
        return TorrentCellContent(
            shape: .text,
            text: text,
            font: monoDigitFont,
            color: .secondaryLabelColor,
            alignment: .right,
            toolTip: nil,
            accessibilityLabel: "\(text) \(label)")
    }

    private static func durationContent(_ seconds: Int64, label: String) -> TorrentCellContent {
        guard seconds > 0 else {
            return TorrentCellContent(
                shape: .text,
                text: "\u{2014}",
                font: monoDigitFont,
                color: .tertiaryLabelColor,
                alignment: .right,
                toolTip: nil,
                accessibilityLabel: "no time \(label)")
        }
        let text = ColumnFormatters.humanizedDuration(seconds)
        return TorrentCellContent(
            shape: .text,
            text: text,
            font: monoDigitFont,
            color: .secondaryLabelColor,
            alignment: .right,
            toolTip: nil,
            accessibilityLabel: "\(text) \(label)")
    }

    private static func limitContent(limited: Bool, text: String?, label: String) -> TorrentCellContent {
        guard limited, let text else {
            return TorrentCellContent(
                shape: .text,
                text: "\u{2014}",
                font: monoDigitFont,
                color: .tertiaryLabelColor,
                alignment: .right,
                toolTip: nil,
                accessibilityLabel: "no \(label)")
        }
        return TorrentCellContent(
            shape: .text,
            text: text,
            font: monoDigitFont,
            color: .secondaryLabelColor,
            alignment: .right,
            toolTip: nil,
            accessibilityLabel: "\(text) \(label)")
    }

    private static func speedContent(_ bytesPerSecond: Int64, color: NSColor) -> TorrentCellContent {
        let fullText = ColumnFormatters.humanizedSpeed(bytesPerSecond)
        if bytesPerSecond == 0 {
            return TorrentCellContent(
                shape: .text,
                text: fullText,
                font: monoDigitFont,
                color: .tertiaryLabelColor,
                alignment: .right,
                toolTip: nil,
                accessibilityLabel: fullText)
        }
        let parts = ColumnFormatters.speedParts(bytesPerSecond)
        return TorrentCellContent(
            shape: .twoPart,
            text: parts.value,
            font: monoDigitFont,
            color: color,
            alignment: .right,
            toolTip: nil,
            accessibilityLabel: fullText,
            secondaryText: parts.unit,
            secondaryFont: caption2Font,
            secondaryColor: color.blended(withFraction: 0.4, of: .systemGray) ?? color)
    }

    private static func etaColor(_ status: TorrentStatus) -> NSColor {
        switch status {
        case .downloading, .checking: return .labelColor
        default: return .secondaryLabelColor
        }
    }

    private static func ratioContent(_ ratio: Double) -> (String, NSColor) {
        guard ratio > 0 else { return (ColumnFormatters.ratio(ratio), .secondaryLabelColor) }
        let text = ColumnFormatters.ratio(ratio)
        let color: NSColor
        if ratio >= 1.0 {
            color = .systemGreen
        } else if ratio >= 0.5 {
            color = .systemOrange
        } else {
            color = .systemRed
        }
        return (text, color)
    }

    private static func statusContent(_ status: TorrentStatus) -> (NSColor, String) {
        (status.nsDisplayColor, status.displayLabel)
    }

    private static func priorityAXLabel(_ priority: TorrentPriority) -> String {
        switch priority {
        case .high: return "high priority"
        case .low: return "low priority"
        case .normal: return "normal priority"
        }
    }
}
