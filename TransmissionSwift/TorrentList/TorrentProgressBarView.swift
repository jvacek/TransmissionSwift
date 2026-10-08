import AppKit

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

    /// Re-resolves the track/fill `cgColor`s when the appearance changes. `withAlphaComponent`
    /// and `cgColor` both snapshot the active appearance, so without this the bar
    /// keeps its old-appearance colour until a content reload.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFill()
    }

    private func updateFill() {
        let clamped = min(max(progress, 0), 1)
        let width = bounds.width * CGFloat(clamped)
        fillLayer.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        // A light grey (label colour at ~10%) so the track reads as empty space
        // behind the tinted fill instead of a dark bezel. `cgColor` snapshots the
        // appearance it is converted under, so resolve while this view's
        // appearance is the drawing appearance.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let track = NSColor.labelColor.withAlphaComponent(0.1)
            trackLayer.backgroundColor = track.cgColor
            let fill = tintColor ?? .labelColor
            fillLayer.backgroundColor = fill.cgColor
        }
    }
}
