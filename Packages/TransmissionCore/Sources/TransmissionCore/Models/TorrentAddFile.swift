// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// One file of a `.torrent` the user is about to add, with the per-file choice
/// the Add Torrent sheet edits. `index` is the file's position in the torrent's
/// `info.files` list, which is what the daemon's `files-wanted` and priority
/// arguments reference.
public struct TorrentAddFile: Identifiable, Equatable, Sendable {
    public var index: Int
    public var path: [String]
    public var length: Int64
    public var wanted: Bool
    public var priority: TorrentPriority

    public var id: Int { index }

    /// Path components joined with `/`, relative to the torrent root.
    public var pathString: String {
        path.joined(separator: "/")
    }

    public init(
        index: Int,
        path: [String],
        length: Int64,
        wanted: Bool = true,
        priority: TorrentPriority = .normal
    ) {
        self.index = index
        self.path = path
        self.length = length
        self.wanted = wanted
        self.priority = priority
    }
}

/// The `torrent-add` file arguments for a set of add-time choices.
///
/// Nil when every file keeps the daemon default (wanted, normal priority), so
/// an add where the user changed nothing sends exactly the payload it did
/// before file selection existed.
struct TorrentAddFileSelection: Equatable, Sendable {
    var filesWanted: [Int]? = nil
    var filesUnwanted: [Int]? = nil
    var priorityHigh: [Int]? = nil
    var priorityNormal: [Int]? = nil
    var priorityLow: [Int]? = nil

    init(files: [TorrentAddFile]) {
        guard files.contains(where: { !$0.wanted || $0.priority != .normal }) else {
            return
        }
        // The spec treats an empty array as "all files", so an empty set must
        // be omitted rather than sent.
        filesWanted = Self.list(files.filter(\.wanted).map(\.index))
        filesUnwanted = Self.list(files.filter { !$0.wanted }.map(\.index))
        priorityHigh = Self.list(
            files.filter { $0.wanted && $0.priority == .high }.map(\.index))
        priorityNormal = Self.list(
            files.filter { $0.wanted && $0.priority == .normal }.map(\.index))
        priorityLow = Self.list(
            files.filter { $0.wanted && $0.priority == .low }.map(\.index))
    }

    private static func list(_ indices: [Int]) -> [Int]? {
        indices.isEmpty ? nil : indices
    }
}
