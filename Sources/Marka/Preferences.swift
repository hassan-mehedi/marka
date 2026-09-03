import AppKit

// User settings backed by UserDefaults. Font choices override the theme's
// fonts; a zero size or empty name means "use the theme's".
@MainActor
final class Preferences {
    static let shared = Preferences()
    static let didChange = Notification.Name("MarkaPreferencesDidChange")

    enum Key: String, CaseIterable {
        case editorFontName = "MarkaEditorFontName"
        case editorFontSize = "MarkaEditorFontSize"
        case codeFontName = "MarkaCodeFontName"
        case codeFontSize = "MarkaCodeFontSize"
        case lineWidth = "MarkaLineWidth"
        case imageFolder = "MarkaImageFolder"
        case spellCheck = "MarkaSpellCheck"
        case autocorrect = "MarkaAutocorrect"
        case autosave = "MarkaAutosave"
        case smartPunctuation = "MarkaSmartPunctuation"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.spellCheck.rawValue: true, Key.imageFolder.rawValue: "assets"])
    }

    var editorFontName: String? {
        get { nonEmpty(defaults.string(forKey: Key.editorFontName.rawValue)) }
        set { set(newValue, for: .editorFontName) }
    }

    var editorFontSize: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.editorFontSize.rawValue)) }
        set { set(newValue > 0 ? Double(newValue) : nil, for: .editorFontSize) }
    }

    var codeFontName: String? {
        get { nonEmpty(defaults.string(forKey: Key.codeFontName.rawValue)) }
        set { set(newValue, for: .codeFontName) }
    }

    var codeFontSize: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.codeFontSize.rawValue)) }
        set { set(newValue > 0 ? Double(newValue) : nil, for: .codeFontSize) }
    }

    // Maximum text column width in points; zero lets text fill the window.
    var lineWidth: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.lineWidth.rawValue)) }
        set { set(newValue > 0 ? Double(newValue) : nil, for: .lineWidth) }
    }

    // Folder next to the document where pasted images are saved.
    var imageFolder: String {
        get { nonEmpty(defaults.string(forKey: Key.imageFolder.rawValue)) ?? "assets" }
        set { set(newValue.trimmingCharacters(in: .whitespaces), for: .imageFolder) }
    }

    var spellCheck: Bool {
        get { defaults.bool(forKey: Key.spellCheck.rawValue) }
        set { set(newValue, for: .spellCheck) }
    }

    var autocorrect: Bool {
        get { defaults.bool(forKey: Key.autocorrect.rawValue) }
        set { set(newValue, for: .autocorrect) }
    }

    var autosave: Bool {
        get { defaults.bool(forKey: Key.autosave.rawValue) }
        set { set(newValue, for: .autosave) }
    }

    var smartPunctuation: Bool {
        get { defaults.bool(forKey: Key.smartPunctuation.rawValue) }
        set { set(newValue, for: .smartPunctuation) }
    }

    nonisolated static var autosaveEnabled: Bool {
        UserDefaults.standard.bool(forKey: Key.autosave.rawValue)
    }

    func apply(to theme: Theme) -> Theme {
        var result = theme
        if let editorFontName { result.baseFontName = editorFontName }
        if editorFontSize > 0 { result.baseFontSize = editorFontSize }
        if let codeFontName { result.codeFontName = codeFontName }
        if codeFontSize > 0 { result.codeFontSize = codeFontSize }
        return result
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func set(_ value: Any?, for key: Key) {
        if let value {
            defaults.set(value, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
