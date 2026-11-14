// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

/// A tag "chip" rendered as a fully-rounded capsule that hugs its text. It
/// keeps an intrinsic size of label-width plus padding, so it never stretches
/// to fill a cell. Coloured tags get a flat solid fill with contrast text, like
/// Finder; uncoloured tags get a translucent neutral fill and a hairline border
/// so they don't dissolve into the row.
final class TagPillView: NSView {
    static let horizontalPadding: CGFloat = 8
    static let minHeight: CGFloat = 18

    private let textLabel = NSTextField(labelWithString: "")
    private let fillLayer = CALayer()
    private let borderLayer = CAShapeLayer()
    private var fillColor: NSColor?
    private var foregroundColor: NSColor?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        fillLayer.zPosition = 0
        borderLayer.zPosition = 1
        layer?.addSublayer(fillLayer)
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
        // it's black/white at 40%, far too dark. Resolve cgColors while this
        // view's appearance is current, like the cell dot and progress bar.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let effectiveBackground =
                fillColor
                ?? NSColor.labelColor.withAlphaComponent(0.06)
            fillLayer.backgroundColor = effectiveBackground.cgColor
            borderLayer.strokeColor =
                fillColor == nil ? NSColor.labelColor.withAlphaComponent(0.16).cgColor : nil
        }
        borderLayer.lineWidth = 1
        borderLayer.fillColor = nil
        CATransaction.commit()
    }
}
