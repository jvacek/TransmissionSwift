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
            && lhs.torrent.label == rhs.torrent.label
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
    static func make(
        for column: TransmissionCore.TableColumn,
        row: TorrentRowDisplay,
        downloadDirectoryBase: String?
    ) -> TorrentCellContent {
        switch column {
        case .name:
            return TorrentCellContent(
                shape: .dotAndText,
                text: row.torrent.name,
                font: bodyFont,
                color: .labelColor,
                alignment: .left,
                toolTip: nil,
                accessibilityLabel: row.torrent.name,
                dotColor: row.torrent.status.nsDisplayColor)
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
            if let label = row.torrent.label, !label.isEmpty {
                return TorrentCellContent(
                    shape: .pill,
                    text: label,
                    font: bodyFont,
                    color: .labelColor,
                    alignment: .left,
                    toolTip: nil,
                    accessibilityLabel: label)
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
        if lastShape != content.shape {
            // Rebuild the subview arrangement. Per-column reuse means the shape
            // is normally constant for a cell's lifetime; this only runs on the
            // first configure or if the reuse pool ever mixes columns.
            for view in stack.arrangedSubviews {
                stack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            lastShape = content.shape
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
                let label = makeLabel()
                label.setContentHuggingPriority(.defaultLow, for: .horizontal)
                label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                stack.addArrangedSubview(label)
                self.dotView = dot
                self.label = label
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
                let label = makeLabel()
                // Hug the text so the pill background stays a pill, not a full-width bar.
                label.setContentHuggingPriority(.required, for: .horizontal)
                stack.addArrangedSubview(label)
                self.label = label
            }
        }
        apply(content)
    }

    private func apply(_ content: TorrentCellContent) {
        switch content.shape {
        case .text:
            configureLabel(content)
        case .pill:
            configureLabel(content)
            label?.wantsLayer = true
            label?.layer?.cornerRadius = 4
            label?.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.5).cgColor
        case .dotAndText:
            configureLabel(content)
            dotView?.layer?.backgroundColor = (content.dotColor ?? .labelColor).cgColor
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
