// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppIntents

/// A user-facing failure surfaced to Shortcuts. `CustomLocalizedStringResourceConvertible`
/// makes the message show verbatim instead of a generic "the action failed".
struct IntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String

    var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: message)
    }
}
