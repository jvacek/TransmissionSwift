import AppKit
import TransmissionCore

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
                // Text first, symbol as a trailing indicator — matches the
                // files-tab / inspector dropdowns where the chevron sits after
                // the priority label.
                let label = makeLabel()
                label.setContentHuggingPriority(.defaultLow, for: .horizontal)
                label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                stack.addArrangedSubview(label)
                let image = NSImageView()
                image.translatesAutoresizingMaskIntoConstraints = false
                image.setAccessibilityElement(false)
                image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
                stack.spacing = 2
                stack.addArrangedSubview(image)
                self.label = label
                self.symbolImageView = image
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
            setDotColor(content.dotColor, for: dotView)
            for (index, tagDot) in trailingDotViews.enumerated() {
                setDotColor(content.trailingDotColors?[index], for: tagDot)
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

    /// Re-applies the layer-based dot colours when the system appearance flips.
    /// `CALayer.backgroundColor` is a static `cgColor` snapshot, so it does not
    /// follow light/dark on its own — `TagPillView` already overrides this hook
    /// for its pills; the status/tag dots need the same treatment, otherwise
    /// they keep their old-appearance colour until a content reload happens.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard let content, content.shape == .dotAndText else { return }
        setDotColor(content.dotColor, for: dotView)
        for (index, tagDot) in trailingDotViews.enumerated() {
            setDotColor(content.trailingDotColors?[index], for: tagDot)
        }
    }

    /// Resolves `color` against this cell's current appearance before handing it
    /// to a layer. `NSColor.cgColor` snapshots the appearance it is converted
    /// under, so resolving explicitly keeps the resolved colour in step with
    /// `effectiveAppearance` rather than whichever appearance was active at the
    /// first conversion.
    private func setDotColor(_ color: NSColor?, for view: NSView?) {
        guard let view else { return }
        // `NSColor.cgColor` snapshots the appearance it is converted under, so
        // resolve it while this cell's appearance is the drawing appearance —
        // a bare `cgColor` would bake in whichever appearance was active at the
        // first conversion.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = (color ?? .labelColor).cgColor
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
