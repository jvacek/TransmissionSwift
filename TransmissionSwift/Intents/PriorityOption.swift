// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents
import TransmissionCore

/// Bandwidth priority as a Shortcuts-pickable enum. Maps to the core
/// `TorrentPriority` (which can't conform to `AppEnum` without importing
/// AppIntents into `TransmissionCore`).
enum PriorityOption: String, AppEnum, CaseIterable, Sendable {
    case low
    case normal
    case high

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Priority")
    static let caseDisplayRepresentations: [PriorityOption: DisplayRepresentation] = [
        .low: "Low",
        .normal: "Normal",
        .high: "High",
    ]

    var domain: TorrentPriority {
        switch self {
        case .low: .low
        case .normal: .normal
        case .high: .high
        }
    }
}
