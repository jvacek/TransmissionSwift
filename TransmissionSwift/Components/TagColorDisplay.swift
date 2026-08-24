import AppKit
import SwiftUI
import TransmissionCore

extension TagColor {
    /// SwiftUI colour for dots, chips and swatches. System colours adapt to
    /// light/dark and mirror Finder's palette.
    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .gray: return .gray
        }
    }

    var nsColor: NSColor {
        switch self {
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .gray: return .systemGray
        }
    }

    /// Text colour to sit on a solid `nsColor`/`color` fill. Yellow is light
    /// enough to need dark text; every other tag colour takes white.
    var nsPillForeground: NSColor {
        self == .yellow ? .black : .white
    }

    var pillForeground: Color {
        self == .yellow ? .black : .white
    }
}

/// Finder-style colour picker: one row per colour with a coloured circle and a
/// checkmark on the current assignment, plus a "No Colour" item. Reusable as
/// the content of a `.contextMenu` or a `Menu`.
///
/// macOS menus render SF Symbol icons as monochrome templates, so `circle.fill`
/// with a `.foregroundStyle` comes out black. We instead hand each row a drawn
/// `NSImage` — a real coloured circle (plus white/dark checkmark) — which
/// AppKit shows in full colour.
struct TagColorPickerMenu: View {
    let current: TagColor?
    let onPick: (TagColor?) -> Void

    var body: some View {
        ForEach(TagColor.allCases, id: \.self) { color in
            Button {
                onPick(color)
            } label: {
                Label {
                    Text(color.displayName)
                } icon: {
                    Image(nsImage: TagColorMenuImage.make(color: color, selected: current == color))
                }
            }
        }
        if current != nil {
            Divider()
            Button("No Colour") { onPick(nil) }
        }
    }
}

/// Draws the coloured-circle NSImage a macOS menu item can display. The
/// checkmark is a tinted SF Symbol (white, or black on yellow) centred over the
/// circle — crisper than a hand-drawn path.
enum TagColorMenuImage {
    static func make(color: TagColor, selected: Bool) -> NSImage {
        let size = NSSize(width: 15, height: 15)
        let checkImage = selected ? tintedCheckmark(color: color) : nil
        return NSImage(size: size, flipped: false) { rect in
            color.nsColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5)).fill()
            if let checkImage {
                let side = checkImage.size.width
                let checkRect = NSRect(
                    x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
                checkImage.draw(in: checkRect, from: .zero, operation: .sourceOver, fraction: 1)
            }
            return true
        }
    }

    private static func tintedCheckmark(color: TagColor) -> NSImage? {
        let checkColor: NSColor = color == .yellow ? .black : .white
        guard
            let symbol = NSImage(
                systemSymbolName: "checkmark", accessibilityDescription: nil
            )?.withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        else { return nil }
        symbol.isTemplate = true
        let tinted = symbol.copy() as! NSImage
        tinted.lockFocus()
        checkColor.set()
        NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
    }
}

/// Small tag-colour indicator: a filled circle in the tag's colour, or a muted
/// placeholder when uncoloured. Used for sidebar rows, inspector chips, and the
/// Tags settings pane.
struct TagColorDot: View {
    let color: TagColor?

    var body: some View {
        Circle()
            .fill(color?.color ?? Color.secondary.opacity(0.45))
            .frame(width: 8, height: 8)
    }
}

/// A tag chip with the same visual language as the table's native pills: a
/// fully-rounded capsule with a solid tag-colour fill (or a translucent neutral
/// fill), a hairline border and a subtle top sheen. Used by the inspector's
/// label chips and the tag input field, so a tag looks identical everywhere.
struct TagPill: View {
    let label: String
    var color: TagColor? = nil
    var font: Font = .caption

    var body: some View {
        Text(label)
            .font(font)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(color?.pillForeground ?? .primary)
            .modifier(TagCapsuleBackground(color: color))
    }
}

/// Shared capsule treatment for tags: tag-colour fill (or a light translucent
/// neutral), a subtle top sheen and a hairline border. Keeps every tag surface
/// — table pill, inspector chip, input chip, suggestion row — looking
/// identical. The neutral fill is the label colour at ~6% (NOT
/// `quaternaryLabelColor.withAlphaComponent(0.4)`, which is black/white at 40%
/// and far too dark against label-coloured text).
struct TagCapsuleBackground: ViewModifier {
    let color: TagColor?

    func body(content: Content) -> some View {
        content.background {
            Capsule()
                .fill(color?.color ?? Color.primary.opacity(0.06))
                .overlay(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                )
                .overlay(
                    Capsule().strokeBorder(
                        Color.primary.opacity(0.16),
                        lineWidth: 1
                    )
                )
        }
    }
}
