import AppIntents
import TransmissionCore
import UniformTypeIdentifiers

/// Adds a `.torrent` file or magnet link to a server, with the options the
/// daemon's `torrent-add` accepts.
struct AddTorrentIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Torrent or Magnet"
    static var description: IntentDescription? {
        IntentDescription("Adds a torrent file or magnet link to a Transmission server.")
    }
    static let openAppWhenRun = false

    @Parameter(title: "Magnet Link")
    var magnet: URL?

    /// `.data` because App Intents' metadata processor can't resolve the app's
    /// imported `org.bittorrent.torrent` UTI; the daemon rejects non-torrent
    /// payloads anyway.
    @Parameter(title: "Torrent File", supportedContentTypes: [.data])
    var file: IntentFile?

    @Parameter(title: "Server")
    var server: ServerEntity?

    @Parameter(title: "Add Paused")
    var paused: Bool?

    @Parameter(title: "Destination Folder")
    var destination: String?

    @Parameter(title: "Labels")
    var labels: [String]?

    @Parameter(title: "Priority")
    var priority: PriorityOption?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let environment = try AppEnvironment.require()
        let (profile, service) = try environment.requireService(server)

        let magnetURL: String?
        let fileURL: URL?
        let what: String
        switch (magnet, file) {
        case (let link?, nil):
            magnetURL = link.absoluteString
            fileURL = nil
            what = "magnet link"
        case (nil, let data?):
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(data.filename.isEmpty ? "upload.torrent" : data.filename)
            try data.data.write(to: url, options: .atomic)
            magnetURL = nil
            fileURL = url
            what = data.filename
        default:
            throw IntentError(message: "Provide exactly one of a magnet link or a torrent file.")
        }

        let startWhenAdded = !(paused ?? false)
        do {
            try await service.add(
                fileURL: fileURL,
                magnetURL: magnetURL,
                destination: destination ?? "",
                labels: labels ?? [],
                priority: (priority ?? .normal).domain,
                startWhenAdded: startWhenAdded)
        } catch {
            throw IntentError(message: error.localizedDescription)
        }

        let summary = "Added \(what) to \(profile.label)\(startWhenAdded ? "" : " (paused)")."
        return .result(dialog: "\(summary)")
    }
}
