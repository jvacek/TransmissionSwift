// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import TransmissionCore

/// Pure sort-descriptor normalisation for the single-sort torrent table. The
/// caller performs the AppKit collapse; this only decides which column to
/// forward.
nonisolated enum TorrentTableSort {
    /// AppKit promotes the clicked column to PRIMARY of its descriptor list,
    /// keeping older entries as secondaries. This is a single-sort table, so
    /// take the primary (`.first` — `.last` is the oldest secondary, the
    /// original bug) and resolve it to a table column. Nil when there is
    /// nothing actionable.
    static func normalize(
        _ descriptors: [NSSortDescriptor]
    ) -> (column: TransmissionCore.TableColumn, ascending: Bool)? {
        guard let primary = descriptors.first,
            let key = primary.key,
            let column = TransmissionCore.TableColumn(rawValue: key)
        else { return nil }
        return (column, primary.ascending)
    }
}
