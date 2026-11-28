// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import TransmissionCore

/// User-selectable interface language. `system` follows macOS; the other cases
/// pin the app to a specific `.lproj` bundle so the change applies immediately.
nonisolated enum InterfaceLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return L10n.text("System Default")
        case .english: return "English"
        case .simplifiedChinese: return "中文（简体）"
        }
    }

    var locale: Locale {
        switch self {
        case .system: return .current
        case .english, .simplifiedChinese: return Locale(identifier: rawValue)
        }
    }

    static func current(defaults: UserDefaults = .standard) -> InterfaceLanguage {
        if AppProcess.isTestRunner { return .english }
        return defaults.string(forKey: PreferenceKeys.interfaceLanguage)
            .flatMap(InterfaceLanguage.init(rawValue:)) ?? .system
    }
}

private nonisolated final class LocalizationBundleCache: @unchecked Sendable {
    private let lock = NSLock()
    private var bundles: [InterfaceLanguage: Bundle] = [:]

    func bundle(for language: InterfaceLanguage) -> Bundle {
        guard language != .system else { return .main }
        lock.lock()
        defer { lock.unlock() }
        if let cached = bundles[language] { return cached }
        let bundle =
            Bundle.main.path(forResource: language.rawValue, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? .main
        bundles[language] = bundle
        return bundle
    }
}

/// App-facing localization lookup. Keys are the English source strings, so a
/// missing translation naturally falls back to readable English.
nonisolated enum L10n {
    private static let cache = LocalizationBundleCache()

    static var language: InterfaceLanguage { InterfaceLanguage.current() }
    static var locale: Locale { language.locale }

    static func text(_ key: String, language: InterfaceLanguage? = nil) -> String {
        let resolvedLanguage = language ?? InterfaceLanguage.current()
        return cache.bundle(for: resolvedLanguage)
            .localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, language: InterfaceLanguage? = nil, _ args: CVarArg...) -> String {
        let resolvedLanguage = language ?? InterfaceLanguage.current()
        return String(
            format: text(key, language: resolvedLanguage),
            locale: resolvedLanguage.locale,
            arguments: args)
    }

    static func date(
        _ date: Date,
        date dateStyle: Date.FormatStyle.DateStyle,
        time timeStyle: Date.FormatStyle.TimeStyle
    ) -> String {
        date.formatted(
            Date.FormatStyle(
                date: dateStyle, time: timeStyle, locale: locale,
                calendar: .autoupdatingCurrent, timeZone: .autoupdatingCurrent,
                capitalizationContext: .standalone))
    }

    static func relativeDate(
        _ date: Date, presentation: Date.RelativeFormatStyle.Presentation = .numeric,
        unitsStyle: Date.RelativeFormatStyle.UnitsStyle = .wide
    ) -> String {
        date.formatted(.relative(presentation: presentation, unitsStyle: unitsStyle).locale(locale))
    }
}
