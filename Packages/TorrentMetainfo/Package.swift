// swift-tools-version: 6.2

// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import PackageDescription

// Mirrors the app target's Swift 6 + "Approachable Concurrency" settings so code
// keeps its semantics when it moves between the app and a package. The packages
// deliberately omit the app's MainActor default isolation (ARCHITECTURE.md §4).
let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "TorrentMetainfo",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "TorrentMetainfo", targets: ["TorrentMetainfo"])
    ],
    targets: [
        .target(
            name: "TorrentMetainfo",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "TorrentMetainfoTests",
            dependencies: ["TorrentMetainfo"],
            resources: [
                .copy("Fixtures")
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
