// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Testing

@testable import TransmissionSwift

/// The preferences scene's empty title used to leak a blank entry into the
/// Window menu. The excluder clears it; this pins the AppKit behaviour it relies
/// on.
@Suite("Preferences window menu")
struct PreferencesWindowMenuTests {
    @Test @MainActor func excluderHidesItsWindowFromTheWindowMenu() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: true)
        #expect(!window.isExcludedFromWindowsMenu)

        window.contentView = WindowMenuExcluder.ExcludedWindowView()

        #expect(window.isExcludedFromWindowsMenu)
    }
}
