import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var isDarkMode: Bool {
        didSet { defaults.set(isDarkMode, forKey: Keys.isDarkMode) }
    }

    @Published var subtitleLanguage: String {
        didSet { defaults.set(subtitleLanguage, forKey: Keys.subtitleLanguage) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isDarkMode = defaults.object(forKey: Keys.isDarkMode) as? Bool ?? true
        self.subtitleLanguage = defaults.string(forKey: Keys.subtitleLanguage) ?? "vi"
    }

    private enum Keys {
        static let isDarkMode = "cineviet_ios_dark_mode"
        static let subtitleLanguage = "cineviet_ios_subtitle_language"
    }
}
