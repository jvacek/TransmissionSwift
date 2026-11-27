// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Testing

@testable import TransmissionSwift

/// A frame autosaved on a display that is gone (or a bigger resolution) is
/// restored on every launch, and macOS 27 can throw while placing it.
@Suite("Restored window frame")
struct RestoredWindowFrameTests {
    /// The built-in display, 1800×1130 points.
    private let screen = CGRect(x: 0, y: 0, width: 1800, height: 1130)
    /// A second display to its right, 1800×1130 points.
    private let secondScreen = CGRect(x: 1800, y: 0, width: 1800, height: 1130)

    /// The eight numbers as a frame and the display they were saved on.
    private func parsed(_ value: String) -> (frame: CGRect, screen: CGRect)? {
        let values = value.split(separator: " ").compactMap { Double($0) }
        guard values.count == 8 else { return nil }
        return (
            CGRect(x: values[0], y: values[1], width: values[2], height: values[3]),
            CGRect(x: values[4], y: values[5], width: values[6], height: values[7])
        )
    }

    @Test func frameThatFitsIsLeftAlone() {
        let stored = "214 273 616 652 0 0 1800 1130"
        #expect(RestoredWindowFrame.clamped(stored, screens: [screen]) == nil)
    }

    @Test func frameWiderThanTheDisplayIsShrunkAndCentred() {
        let stored = "0 63 3000 2000 0 0 1800 1130"
        let repaired = RestoredWindowFrame.clamped(stored, screens: [screen])
        let values = repaired.flatMap(parsed)
        #expect(values?.frame == CGRect(x: 0, y: 0, width: 1800, height: 1130))
        #expect(values?.screen == screen)
    }

    @Test func frameOnAMissingDisplayMovesToThePrimaryOne() {
        // Saved on a display to the right that is no longer connected.
        let stored = "2200 300 900 600 1800 0 1800 1130"
        let repaired = RestoredWindowFrame.clamped(stored, screens: [screen])
        let values = repaired.flatMap(parsed)
        #expect(values?.frame == CGRect(x: 450, y: 265, width: 900, height: 600))
        #expect(values?.screen == screen)
    }

    @Test func frameSpanningTwoDisplaysIsAPlacementNotADamage() {
        let stored = "1700 200 800 600 0 0 1800 1130"
        #expect(RestoredWindowFrame.clamped(stored, screens: [screen, secondScreen]) == nil)
    }

    @Test func unreadableValueIsLeftAlone() {
        #expect(RestoredWindowFrame.clamped("", screens: [screen]) == nil)
        #expect(RestoredWindowFrame.clamped("214 273 616", screens: [screen]) == nil)
        #expect(RestoredWindowFrame.clamped("a b c d e f g h", screens: [screen]) == nil)
    }

    @Test func noScreensLeavesTheValueAlone() {
        #expect(RestoredWindowFrame.clamped("0 0 10 10 0 0 1800 1130", screens: []) == nil)
    }

    @Test @MainActor func repairIsWrittenBackToTheDefaults() {
        let name = "RestoredWindowFrameTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let key = RestoredWindowFrame.key(for: "main")
        defaults.set("2200 300 900 600 1800 0 1800 1130", forKey: key)

        let repaired = RestoredWindowFrame.clampToDisplays(
            named: "main", screens: [screen], defaults: defaults)

        #expect(repaired != nil)
        #expect(defaults.string(forKey: key) == repaired)
    }

    @Test @MainActor func fittingFrameIsNotWrittenBack() {
        let name = "RestoredWindowFrameTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let key = RestoredWindowFrame.key(for: "main")
        let stored = "214 273 616 652 0 0 1800 1130"
        defaults.set(stored, forKey: key)

        #expect(
            RestoredWindowFrame.clampToDisplays(
                named: "main", screens: [screen], defaults: defaults) == nil)
        #expect(defaults.string(forKey: key) == stored)
    }
}
