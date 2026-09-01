import AppKit

@MainActor
final class ThemeManager {
    static let shared = ThemeManager()
    static let didChange = Notification.Name("MarkaThemeDidChange")
    private static let defaultsKey = "MarkaThemeName"

    private(set) var current: Theme

    var themes: [Theme] {
        Theme.builtIn + userThemes
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey)
        let available = Theme.builtIn + Self.loadUserThemes()
        current = available.first { $0.name == saved } ?? .systemTheme
    }

    func select(named name: String) {
        guard let theme = themes.first(where: { $0.name == name }), theme != current else { return }
        current = theme
        UserDefaults.standard.set(name, forKey: Self.defaultsKey)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    static var userThemesDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Marka/Themes", isDirectory: true)
    }

    private var userThemes: [Theme] { Self.loadUserThemes() }

    private static func loadUserThemes() -> [Theme] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: userThemesDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return (try? JSONDecoder().decode(ThemeFile.self, from: data))?.theme
            }
    }
}
