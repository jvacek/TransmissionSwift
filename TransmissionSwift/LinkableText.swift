import AppKit
import Foundation
import SwiftUI

/// Message text with embedded URLs rendered as underlined, browser-opening
/// links. Hovering the message shows a pointing-hand cursor when it contains
/// a link.
struct LinkableText: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(attributedText)
            .onHover { hovering in
                guard hasLinks else { return }
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private var hasLinks: Bool {
        !Self.urls(in: text).isEmpty
    }

    private var attributedText: AttributedString {
        var attributed = AttributedString(text)
        attributed.foregroundColor = color
        for (url, nsRange) in Self.urls(in: text) {
            guard let range = Range(nsRange, in: attributed) else { continue }
            attributed[range].link = url
            attributed[range].underlineStyle = .single
        }
        return attributed
    }

    private static let urlDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    private static func urls(in text: String) -> [(url: URL, nsRange: NSRange)] {
        guard let detector = urlDetector else { return [] }
        let nsText = text as NSString
        return detector.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            .compactMap { match in
                guard let url = match.url else { return nil }
                return (url, match.range)
            }
    }
}
