import AppIntents

/// A user-facing failure surfaced to Shortcuts. `CustomLocalizedStringResourceConvertible`
/// makes the message show verbatim instead of a generic "the action failed".
struct IntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String

    var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: message)
    }
}
