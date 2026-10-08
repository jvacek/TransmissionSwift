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
        guard let mutations = service as? any TorrentMutating else {
            throw IntentError(message: "This server is read-only.")
        }
        // A file payload is spooled into a unique temp directory so a crafted
        // `filename` can't escape it, and removed when `perform` returns.
        var stagedDirectory: URL?
        defer { if let stagedDirectory { try? FileManager.default.removeItem(at: stagedDirectory) } }

        let magnetURL: String?
        let fileURL: URL?
        let what: String
        switch (magnet, file) {
        case (let link?, nil):
            magnetURL = link.absoluteString
            fileURL = nil
            what = "magnet link"
        case (nil, let data?):
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("TransmissionSwift-Intent-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            stagedDirectory = directory
            let name = (data.filename as NSString).lastPathComponent
            let url = directory.appendingPathComponent(name.isEmpty ? "upload.torrent" : name)
            try data.data.write(to: url, options: .atomic)
            magnetURL = nil
            fileURL = url
            what = name.isEmpty ? "torrent file" : name
        default:
            throw IntentError(message: "Provide exactly one of a magnet link or a torrent file.")
        }

        let startWhenAdded = !(paused ?? false)
        do {
            try await mutations.add(
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
