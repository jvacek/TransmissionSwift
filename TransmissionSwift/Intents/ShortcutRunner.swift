import AppKit
import Foundation

/// Runs one of the user's Shortcuts by name, handing it the selected torrents'
/// `transmissionswift://` deep links as text. There is no API to enumerate a
/// user's shortcuts, so the name is typed in Preferences; `URLComponents` does
/// the percent-encoding.
enum ShortcutRunner {
    /// The `shortcuts://run-shortcut` URL for `name` with `input` as its text.
    /// Split out from `run` so the encoding is testable without opening anything.
    static func runURL(named name: String, input: String) -> URL? {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "input", value: "text"),
            URLQueryItem(name: "text", value: input),
        ]
        return components.url
    }

    /// Opens the Shortcuts app on `name`, passing `input` as the shortcut's text
    /// input (one deep link per line).
    @MainActor
    static func run(named name: String, input: String) {
        guard let url = runURL(named: name, input: input) else { return }
        NSWorkspace.shared.open(url)
    }
}
