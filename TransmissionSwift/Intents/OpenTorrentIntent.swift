import AppIntents
import AppKit
import TransmissionCore

/// Opens TransmissionSwift showing a specific torrent — the action Spotlight and
/// Siri use to open an indexed torrent, and a shortcut's way to deep-link into
/// the app.
struct OpenTorrentIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Torrent"
    static var description: IntentDescription? {
        IntentDescription("Opens TransmissionSwift showing a torrent.")
    }
    static let openAppWhenRun = true

    @Parameter(title: "Torrent")
    var target: TorrentEntity

    func perform() async throws -> some IntentResult {
        guard let torrentID = Int(target.id) else {
            throw IntentError(message: "Invalid torrent.")
        }
        let serverID = UUID(uuidString: target.serverID)
        await MainActor.run {
            OpenRequestBus.shared.request = OpenRequest(serverID: serverID, torrentID: torrentID)
            NSApplication.shared.activate()
        }
        return .result()
    }
}
