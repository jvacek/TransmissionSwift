import AppIntents
import TransmissionCore
import UniformTypeIdentifiers

/// Adds a `.torrent` file to a server, with the options the daemon's
/// `torrent-add` accepts.
struct AddTorrentFileIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Torrent File"
    static var description: IntentDescription? {
        IntentDescription("Adds a .torrent file to a Transmission server.")
    }
    static let openAppWhenRun = false

    /// `.data` because App Intents' metadata processor can't resolve the app's
    /// imported `org.bittorrent.torrent` UTI; the daemon rejects non-torrent
    /// payloads anyway.
    @Parameter(title: "Torrent File", supportedContentTypes: [.data])
    var file: IntentFile

    @Parameter(title: "Server")
    var server: ServerEntity?

    @Parameter(title: "Add Paused")
    var paused: Bool?

    @Parameter(title: "Destination Folder")
    var destination: String?

    @Parameter(title: "Labels")
    var labels: [String]?

    @Parameter(title: "Priority", default: .normal)
    var priority: PriorityOption?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = try await addTorrent(
            server: server, link: nil, file: file, paused: paused,
            destination: destination, labels: labels, priority: priority)
        return .result(dialog: "\(dialog)")
    }
}

/// Adds a magnet link or torrent URL to a server. Separate from
/// `AddTorrentFileIntent` because a link and a file are mutually exclusive, and
/// App Intents can't express "exactly one of these two".
struct AddMagnetLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Torrent Link"
    static var description: IntentDescription? {
        IntentDescription("Adds a magnet link or torrent URL to a Transmission server.")
    }
    static let openAppWhenRun = false

    /// Kept named `magnet` so parameter identifiers in existing Shortcuts stay
    /// valid; the title also accepts an http(s) URL.
    @Parameter(title: "Magnet Link or URL")
    var magnet: URL

    @Parameter(title: "Server")
    var server: ServerEntity?

    @Parameter(title: "Add Paused")
    var paused: Bool?

    @Parameter(title: "Destination Folder")
    var destination: String?

    @Parameter(title: "Labels")
    var labels: [String]?

    @Parameter(title: "Priority", default: .normal)
    var priority: PriorityOption?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = try await addTorrent(
            server: server, link: magnet.absoluteString, file: nil, paused: paused,
            destination: destination, labels: labels, priority: priority)
        return .result(dialog: "\(dialog)")
    }
}

/// Shared add path. A file payload is spooled into a unique temp directory so a
/// crafted `filename` can't escape it, and removed when the call returns.
private func addTorrent(
    server: ServerEntity?,
    link: String?,
    file: IntentFile?,
    paused: Bool?,
    destination: String?,
    labels: [String]?,
    priority: PriorityOption?
) async throws -> String {
    let environment = try AppEnvironment.require()
    let (profile, service) = try environment.requireService(server)
    let mutations = try environment.requireMutations(service)

    var stagedDirectory: URL?
    defer { if let stagedDirectory { try? FileManager.default.removeItem(at: stagedDirectory) } }

    let linkURL: String?
    let fileURL: URL?
    let what: String
    if let link {
        linkURL = link
        fileURL = nil
        what = link.hasPrefix("magnet:") ? "magnet link" : "torrent URL"
    } else if let file {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TransmissionSwift-Intent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        stagedDirectory = directory
        let name = (file.filename as NSString).lastPathComponent
        let url = directory.appendingPathComponent(name.isEmpty ? "upload.torrent" : name)
        try file.data.write(to: url, options: .atomic)
        linkURL = nil
        fileURL = url
        what = name.isEmpty ? "torrent file" : name
    } else {
        throw IntentError(message: "Provide a magnet link, torrent URL or torrent file.")
    }

    let startWhenAdded = !(paused ?? false)
    do {
        try await mutations.add(
            fileURL: fileURL,
            linkURL: linkURL,
            destination: destination ?? "",
            labels: labels ?? [],
            priority: (priority ?? .normal).domain,
            startWhenAdded: startWhenAdded,
            files: [])
    } catch {
        throw IntentError(message: error.localizedDescription)
    }

    return "Added \(what) to \(profile.label)\(startWhenAdded ? "" : " (paused)")."
}
