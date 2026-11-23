// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit

/// An app that can open a mapping's URL.
struct HandlerApp: Identifiable, Equatable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

/// LaunchServices lookups for the mapping editor. Each call hits the system,
/// so callers resolve once per scheme rather than from a view's `body`.
enum HandlerAppResolver {
    /// Apps that can open `probe`, plus `selected` (so a picker always shows the
    /// saved value even when the scheme changed). Sorted by display name.
    static func apps(for probe: URL?, selected: String?) -> [HandlerApp] {
        var apps: [HandlerApp] = []
        if let selected {
            apps.append(
                HandlerApp(
                    bundleID: selected,
                    name: MappingLauncher.displayName(for: selected) ?? selected))
        }
        if let probe {
            for appURL in NSWorkspace.shared.urlsForApplications(toOpen: probe) {
                guard let bundle = Bundle(url: appURL), let bundleID = bundle.bundleIdentifier
                else { continue }
                if apps.contains(where: { $0.bundleID == bundleID }) { continue }
                let name =
                    (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
                    ?? bundle.infoDictionary?["CFBundleName"] as? String
                    ?? appURL.deletingPathExtension().lastPathComponent
                apps.append(HandlerApp(bundleID: bundleID, name: name))
            }
        }
        return apps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// The bundle id of the scheme's default handler.
    static func defaultHandler(forScheme scheme: String) -> String? {
        guard
            let url = URL(string: "\(scheme)://probe"),
            let appURL = NSWorkspace.shared.urlForApplication(toOpen: url)
        else { return nil }
        return Bundle(url: appURL)?.bundleIdentifier
    }

    /// The URL scheme of a mapping template, so candidate apps can be probed
    /// even when the full URL can't be built yet. A bare path counts as `file`.
    static func scheme(ofTemplate template: String) -> String? {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: "://") {
            return String(trimmed[..<range.lowerBound]).lowercased()
        }
        return trimmed.hasPrefix("/") ? "file" : nil
    }
}
