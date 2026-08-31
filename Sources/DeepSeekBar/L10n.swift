import Foundation

/// Lightweight localization. English source strings double as keys;
/// translations live in Resources/zh-Hans.lproj/Localizable.strings, which
/// build.sh copies into Contents/Resources so Bundle.main resolves them.
/// Outside a bundled app (swift test / swift run) lookups fall back to the
/// key itself, i.e. English.
enum L10n {
    static func tr(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static func trf(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), arguments: args)
    }
}
