import AppKit

@MainActor
final class ThemeManager {
    static let shared = ThemeManager()
    static let didChange = Notification.Name("MarkaThemeDidChange")
    private static let defaultsKey = "MarkaThemeName"
    private static let scaleKey = "MarkaFontScale"
    static let scaleSteps: ClosedRange<Double> = 0.5...3.0

    private(set) var baseTheme: Theme
    private(set) var fontScale: Double

    // The selected theme with the user's font choices applied and sizes
    // multiplied by the zoom level.
    var current: Theme {
        let themed = Preferences.shared.apply(to: baseTheme)
        guard fontScale != 1 else { return themed }
        var scaled = themed
        scaled.baseFontSize = (themed.baseFontSize * fontScale).rounded()
        scaled.codeFontSize = (themed.codeFontSize * fontScale).rounded()
        return scaled
    }

    var themes: [Theme] {
        Self.merge(builtIn: Theme.builtIn, user: Self.loadUserThemes())
    }

    // Names are how themes are picked, so each appears once: a user theme
    // named like a built-in replaces it, and a second file with the same
    // name is ignored.
    nonisolated static func merge(builtIn: [Theme], user: [Theme]) -> [Theme] {
        var seen = Set<String>()
        let users = user.filter { seen.insert($0.name).inserted }
        let replaced = builtIn.map { theme in users.first { $0.name == theme.name } ?? theme }
        let builtInNames = Set(builtIn.map(\.name))
        return replaced + users.filter { !builtInNames.contains($0.name) }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey)
        let available = Self.merge(builtIn: Theme.builtIn, user: Self.loadUserThemes())
        baseTheme = available.first { $0.name == saved } ?? .systemTheme
        let savedScale = UserDefaults.standard.double(forKey: Self.scaleKey)
        fontScale = Self.scaleSteps.contains(savedScale) ? savedScale : 1
        NotificationCenter.default.addObserver(
            forName: Preferences.didChange, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                NotificationCenter.default.post(name: Self.didChange, object: nil)
            }
        }
    }

    func select(named name: String) {
        guard let theme = themes.first(where: { $0.name == name }), theme != baseTheme else { return }
        baseTheme = theme
        UserDefaults.standard.set(name, forKey: Self.defaultsKey)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func setFontScale(_ scale: Double) {
        let clamped = min(max((scale * 10).rounded() / 10, Self.scaleSteps.lowerBound), Self.scaleSteps.upperBound)
        guard clamped != fontScale else { return }
        fontScale = clamped
        UserDefaults.standard.set(clamped, forKey: Self.scaleKey)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    static var userThemesDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Marka/Themes", isDirectory: true)
    }

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
