import AppKit
import TransmissionCore

/// Projection of a `Torrent` onto exactly the fields the table renders. Single
/// source of truth for what a row "displays": the row-level poll guard compares
/// `[TorrentRowDisplay]`, and `TorrentCellContent.make` reads from it — so the
/// guarded fields and the rendered fields can never drift apart.
struct TorrentRowDisplay: Equatable {
    let torrent: Torrent

    var id: Torrent.ID { torrent.id }

    init(_ torrent: Torrent) {
        self.torrent = torrent
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        // Only the fields the table renders participate in the poll guard; a
        // full `Torrent` equality would deep-compare files/peers/trackers on
        // every tick. Keep this list in sync with `TorrentCellContent.make`:
        // a renderable field must be added to both.
        lhs.torrent.id == rhs.torrent.id
            && lhs.torrent.name == rhs.torrent.name
            && lhs.torrent.hash == rhs.torrent.hash
            && lhs.torrent.size == rhs.torrent.size
            && lhs.torrent.progress == rhs.torrent.progress
            && lhs.torrent.status == rhs.torrent.status
            && lhs.torrent.downloadSpeed == rhs.torrent.downloadSpeed
            && lhs.torrent.uploadSpeed == rhs.torrent.uploadSpeed
            && lhs.torrent.connectedPeerCount == rhs.torrent.connectedPeerCount
            && lhs.torrent.availablePeerCount == rhs.torrent.availablePeerCount
            && lhs.torrent.seedCount == rhs.torrent.seedCount
            && lhs.torrent.eta == rhs.torrent.eta
            && lhs.torrent.ratio == rhs.torrent.ratio
            && lhs.torrent.primaryTracker == rhs.torrent.primaryTracker
            && lhs.torrent.downloadFolder == rhs.torrent.downloadFolder
            && lhs.torrent.addedAt == rhs.torrent.addedAt
            && lhs.torrent.labels == rhs.torrent.labels
            && lhs.torrent.priority == rhs.torrent.priority
            && lhs.torrent.pieces == rhs.torrent.pieces
            && lhs.torrent.havePieces == rhs.torrent.havePieces
            && lhs.torrent.queuePosition == rhs.torrent.queuePosition
            && lhs.torrent.errorMessage == rhs.torrent.errorMessage
    }
}

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
            let (symbol, symbolColor, label) = priorityContent(row.torrent.priority)
            return TorrentCellContent(
                shape: .symbolAndText,
                text: label,
                font: captionFont,
                color: .secondaryLabelColor,
                alignment: .left,
                toolTip: label,
                accessibilityLabel: priorityAXLabel(row.torrent.priority),
                symbolName: symbol,
                symbolColor: symbolColor)
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
        }
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
        if ratio == 0 { return ("\u{2014}", .secondaryLabelColor) }
        let text = String(format: "%.2f", ratio)
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

    private static func priorityContent(_ priority: TorrentPriority) -> (String, NSColor, String) {
        switch priority {
        case .high: return ("chevron.up", .systemOrange, "High")
        case .low: return ("chevron.down", .systemBlue, "Low")
        case .normal: return ("minus", .systemGray, "Normal")
        }
    }

    private static func priorityAXLabel(_ priority: TorrentPriority) -> String {
        switch priority {
        case .high: return "high priority"
        case .low: return "low priority"
        case .normal: return "normal priority"
        }
    }
}

/// Native table cell. Renders `TorrentCellContent` with plain AppKit views and
/// skips re-rendering when the value is unchanged (per-cell change detection).
final class TorrentTableCellView: NSTableCellView {
    /// Horizontal inset shared by body cells and the column headers, so the
    /// title and the cell content line up.
    static let cellInset: CGFloat = 6

    private var content: TorrentCellContent?
    private var stackView: NSStackView?
    private var dotView: NSView?
    private var label: NSTextField?
    private var secondaryLabel: NSTextField?
    private var progressView: TorrentProgressBarView?
    private var symbolImageView: NSImageView?
    private var pillLabels: [TagPillView] = []
    private var trailingDotViews: [NSView] = []
    private var lastShape: TorrentCellContent.Shape?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUpAccessibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUpAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    func configure(content: TorrentCellContent) {
        // AX guard: only touch the label when it actually changed.
        if accessibilityLabel() != content.accessibilityLabel {
            setAccessibilityLabel(content.accessibilityLabel)
        }
        guard content != self.content else { return }
        self.content = content
        toolTip = content.toolTip
        render(content)
    }

    private func render(_ content: TorrentCellContent) {
        let stack = containerStack()
        let pillCountChanged =
            content.shape == .pills && pillLabels.count != (content.pillTexts ?? []).count
        let trailingCountChanged =
            content.shape == .dotAndText
            && trailingDotViews.count != (content.trailingDotColors ?? []).count
        if lastShape != content.shape || pillCountChanged || trailingCountChanged {
            // Rebuild the subview arrangement. Per-column reuse means the shape
            // is normally constant for a cell's lifetime; this runs on the
            // first configure, when the reuse pool mixes columns, or when a
            // `.pills` cell's tag count / a `.dotAndText` cell's tag-dot count
            // changed (labels were edited).
            for view in stack.arrangedSubviews {
                stack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            lastShape = content.shape
            var trailingDots: [NSView] = []
            switch content.shape {
            case .text:
                let label = makeLabel()
                // Fills the cell; `alignment` inside the field handles left/right.
                label.setContentHuggingPriority(.defaultLow, for: .horizontal)
                label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                stack.addArrangedSubview(label)
                self.label = label
            case .dotAndText:
                let dot = makeDot()
                stack.spacing = 6
                stack.addArrangedSubview(dot)
                // A truncating single-line label resists stretching, so `.fill`
                // would otherwise shove spare width into whatever follows it.
                // An explicit flexible spacer absorbs that width, keeping the
                // name at its natural size and the tag-dot cluster pinned to the
                // column's trailing edge.
                let label = makeLabel()
                label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
                label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
                stack.addArrangedSubview(label)
                stack.addArrangedSubview(makeFlexibleSpacer())
                if !(content.trailingDotColors ?? []).isEmpty {
                    let dotsStack = NSStackView()
                    dotsStack.orientation = .horizontal
                    dotsStack.spacing = 4
                    dotsStack.setContentHuggingPriority(.required, for: .horizontal)
                    dotsStack.setContentCompressionResistancePriority(.required, for: .horizontal)
                    for _ in content.trailingDotColors ?? [] {
                        let tagDot = makeDot()
                        dotsStack.addArrangedSubview(tagDot)
                        trailingDots.append(tagDot)
                    }
                    stack.addArrangedSubview(dotsStack)
                }
                self.dotView = dot
                self.label = label
                self.trailingDotViews = trailingDots
            case .progress:
                let bar = TorrentProgressBarView()
                bar.translatesAutoresizingMaskIntoConstraints = false
                bar.setContentHuggingPriority(.defaultLow, for: .horizontal)
                bar.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                stack.addArrangedSubview(bar)
                let percent = makeLabel()
                percent.alignment = .right
                percent.translatesAutoresizingMaskIntoConstraints = false
                percent.widthAnchor.constraint(equalToConstant: 40).isActive = true
                stack.addArrangedSubview(percent)
                self.progressView = bar
                self.secondaryLabel = percent
            case .twoPart:
                // Flexible spacer pushes the value+unit pair to the trailing edge.
                let spacer = NSView()
                spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
                spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                stack.addArrangedSubview(spacer)
                let value = makeLabel()
                let unit = makeLabel()
                stack.addArrangedSubview(value)
                stack.addArrangedSubview(unit)
                self.label = value
                self.secondaryLabel = unit
            case .symbolAndText:
                let image = NSImageView()
                image.translatesAutoresizingMaskIntoConstraints = false
                image.setAccessibilityElement(false)
                image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
                stack.spacing = 2
                stack.addArrangedSubview(image)
                let label = makeLabel()
                label.setContentHuggingPriority(.defaultLow, for: .horizontal)
                label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                stack.addArrangedSubview(label)
                self.symbolImageView = image
                self.label = label
            case .pill:
                let pill = makePill()
                stack.addArrangedSubview(pill)
                stack.addArrangedSubview(makeFlexibleSpacer())
                pillLabels = [pill]
            case .pills:
                stack.spacing = 4
                var madePills: [TagPillView] = []
                for _ in content.pillTexts ?? [] {
                    let pill = makePill()
                    stack.addArrangedSubview(pill)
                    madePills.append(pill)
                }
                // The trailing spacer absorbs all spare column width so the
                // pills hug their text — a single pill never stretches to fill.
                stack.addArrangedSubview(makeFlexibleSpacer())
                pillLabels = madePills
            }
        }
        apply(content)
    }

    private func apply(_ content: TorrentCellContent) {
        switch content.shape {
        case .text:
            configureLabel(content)
        case .pill:
            guard let pill = pillLabels.first else { break }
            pill.configure(
                text: content.text,
                background: content.pillBackgroundColors?.first,
                foreground: content.pillForegroundColors?.first)
        case .pills:
            for (index, pill) in pillLabels.enumerated() {
                pill.configure(
                    text: content.pillTexts?[index] ?? "",
                    background: content.pillBackgroundColors?[index],
                    foreground: content.pillForegroundColors?[index])
            }
        case .dotAndText:
            configureLabel(content)
            dotView?.layer?.backgroundColor = (content.dotColor ?? .labelColor).cgColor
            for (index, tagDot) in trailingDotViews.enumerated() {
                tagDot.layer?.backgroundColor =
                    (content.trailingDotColors?[index] ?? .labelColor).cgColor
            }
        case .progress:
            progressView?.progress = content.progressValue ?? 0
            progressView?.tintColor = content.progressTint
            secondaryLabel?.stringValue = content.percentText ?? ""
            secondaryLabel?.font = content.secondaryFont
            secondaryLabel?.textColor = content.secondaryColor ?? .secondaryLabelColor
        case .twoPart:
            configureLabel(content)
            secondaryLabel?.stringValue = content.secondaryText ?? ""
            secondaryLabel?.font = content.secondaryFont
            secondaryLabel?.textColor = content.secondaryColor ?? .secondaryLabelColor
        case .symbolAndText:
            symbolImageView?.image = NSImage(
                systemSymbolName: content.symbolName ?? "", accessibilityDescription: nil)
            symbolImageView?.contentTintColor = content.symbolColor
            configureLabel(content)
        }
    }

    private func configureLabel(_ content: TorrentCellContent) {
        label?.stringValue = content.text
        label?.font = content.font
        label?.textColor = content.color
        label?.alignment = content.alignment
    }

    private func makeLabel() -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.setAccessibilityElement(false)
        return field
    }

    private func makeDot() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.cornerRadius = 4
        view.setAccessibilityElement(false)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 8),
            view.heightAnchor.constraint(equalToConstant: 8),
        ])
        return view
    }

    private func makePill() -> TagPillView {
        let pill = TagPillView()
        // Hug the text (horizontal) so the pill is its content, and hug its
        // intrinsic height so the row's stack can't stretch it into a tall
        // "olive" capsule. Width is clamped to ≥ height in the view itself, so
        // a fully-truncated pill collapses to a circle rather than a sliver.
        pill.setContentHuggingPriority(.required, for: .horizontal)
        pill.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        pill.setContentHuggingPriority(.required, for: .vertical)
        pill.setContentCompressionResistancePriority(.required, for: .vertical)
        return pill
    }

    /// Absorbs spare width so the leading content hugs instead of stretching.
    private func makeFlexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    private func containerStack() -> NSStackView {
        if let stackView { return stackView }
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.cellInset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.cellInset),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        stackView = stack
        return stack
    }
}

/// A tag "chip" rendered as a fully-rounded capsule that hugs its text. The
/// capsule is drawn with layers (fill + top sheen + hairline border) and keeps
/// an intrinsic size of label-width plus padding, so it never stretches to fill
/// a cell. Coloured tags get a solid fill with contrast text; uncoloured tags
/// get a translucent neutral fill.
final class TagPillView: NSView {
    static let horizontalPadding: CGFloat = 8
    static let minHeight: CGFloat = 18

    private let textLabel = NSTextField(labelWithString: "")
    private let fillLayer = CALayer()
    private let sheenLayer = CAGradientLayer()
    private let borderLayer = CAShapeLayer()
    private var fillColor: NSColor?
    private var foregroundColor: NSColor?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        fillLayer.zPosition = 0
        sheenLayer.zPosition = 1
        borderLayer.zPosition = 2
        layer?.addSublayer(fillLayer)
        layer?.addSublayer(sheenLayer)
        layer?.addSublayer(borderLayer)

        textLabel.font = .systemFont(ofSize: 12)
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.maximumNumberOfLines = 1
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.setAccessibilityElement(false)
        addSubview(textLabel)
        NSLayoutConstraint.activate([
            textLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: Self.horizontalPadding),
            textLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -Self.horizontalPadding),
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            // The intrinsic-size clamp can't stop the stack from COMPRESSING a
            // pill below its text (compression bypasses intrinsic size). A real
            // width ≥ height constraint is what guarantees the pill never gets
            // narrower than its own height — i.e. it collapses to a circle at
            // minimum width instead of a tall "olive" sliver.
            widthAnchor.constraint(greaterThanOrEqualTo: heightAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, background: NSColor?, foreground: NSColor?) {
        textLabel.stringValue = text
        fillColor = background
        foregroundColor = foreground
        textLabel.textColor = foreground ?? .secondaryLabelColor
        applyStyling()
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize {
        let textWidth = textLabel.intrinsicContentSize.width
        let height = max(textLabel.intrinsicContentSize.height + 4, Self.minHeight)
        // Width never dips below height, so a fully-truncated pill collapses to
        // a circle instead of a degenerate sliver.
        let width = max(textWidth + 2 * Self.horizontalPadding, height)
        return NSSize(width: width, height: height)
    }

    override func layout() {
        super.layout()
        // Layer changes here must snap, not animate: during a column/row resize
        // the fill and border must move in lockstep. Implicit Core Animation
        // would otherwise animate them with different interpolation and they
        // visibly lag apart.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let radius = bounds.height / 2
        layer?.cornerRadius = radius
        fillLayer.frame = bounds
        fillLayer.cornerRadius = radius
        sheenLayer.frame = bounds
        sheenLayer.cornerRadius = radius
        // Hairline border inset so the 1px stroke sits fully inside the capsule.
        borderLayer.frame = bounds
        borderLayer.path = CGPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerWidth: max(radius - 0.5, 0),
            cornerHeight: max(radius - 0.5, 0),
            transform: nil)
        CATransaction.commit()
        updateToolTipIfTruncated()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyStyling()
    }

    /// Shows the full label as a hover tooltip only when the pill has truncated
    /// its text (the cell's own toolTip is nil for pill cells).
    private func updateToolTipIfTruncated() {
        let available = max(bounds.width - 2 * Self.horizontalPadding, 0)
        let truncated = available < textLabel.intrinsicContentSize.width - 0.5
        let newTip = truncated ? textLabel.stringValue : nil
        if toolTip != newTip { toolTip = newTip }
    }

    private func applyStyling() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Neutral pills use the same light recipe as the SwiftUI TagPill
        // (label colour at ~6%) so table and inspector chips match exactly.
        // `quaternaryLabelColor.withAlphaComponent(0.4)` is NOT a light grey —
        // it's black/white at 40%, far too dark.
        let effectiveBackground =
            fillColor
            ?? NSColor.labelColor.withAlphaComponent(0.06)
        fillLayer.backgroundColor = effectiveBackground.cgColor
        sheenLayer.colors = [
            NSColor.white.withAlphaComponent(0.14).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor,
        ]
        sheenLayer.locations = [0, 0.55]
        sheenLayer.startPoint = CGPoint(x: 0.5, y: 0)
        sheenLayer.endPoint = CGPoint(x: 0.5, y: 1)
        borderLayer.strokeColor = NSColor.labelColor.withAlphaComponent(0.16).cgColor
        borderLayer.lineWidth = 1
        borderLayer.fillColor = nil
        CATransaction.commit()
    }
}

/// Native linear progress bar. NSProgressIndicator exposes no tint on macOS, so
/// draw a rounded track + fill with layers instead of the system control. The
/// intrinsic height keeps it a thin bar inside the row instead of stretching to
/// the full cell height (matches SwiftUI's `.linear` ProgressView).
final class TorrentProgressBarView: NSView {
    /// Thickness of the bar, matching the system linear progress indicator.
    static let barHeight: CGFloat = 5

    var progress: Double = 0 {
        didSet { updateFill() }
    }
    var tintColor: NSColor? {
        didSet { updateFill() }
    }

    private let trackLayer = CALayer()
    private let fillLayer = CALayer()

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.barHeight)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        trackLayer.cornerRadius = Self.barHeight / 2
        fillLayer.cornerRadius = Self.barHeight / 2
        layer?.addSublayer(trackLayer)
        layer?.addSublayer(fillLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        trackLayer.frame = bounds
        fillLayer.frame = bounds
        updateFill()
    }

    private func updateFill() {
        let clamped = min(max(progress, 0), 1)
        let width = bounds.width * CGFloat(clamped)
        fillLayer.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        trackLayer.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.5).cgColor
        fillLayer.backgroundColor = (tintColor ?? .labelColor).cgColor
    }
}
