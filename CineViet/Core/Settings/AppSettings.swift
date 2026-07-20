import Foundation
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Theo hệ thống"
        case .light: return "Sáng"
        case .dark: return "Tối"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    @Published var subtitleLanguage: String {
        didSet { defaults.set(subtitleLanguage, forKey: Keys.subtitleLanguage) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: Keys.appearance), let appearance = AppAppearance(rawValue: stored) {
            self.appearance = appearance
        } else if let legacy = defaults.object(forKey: Keys.isDarkMode) as? Bool {
            self.appearance = legacy ? .dark : .light
        } else {
            self.appearance = .system
        }
        self.subtitleLanguage = defaults.string(forKey: Keys.subtitleLanguage) ?? "vi"
    }

    private enum Keys {
        static let isDarkMode = "cineviet_ios_dark_mode"
        static let appearance = "cineviet_ios_appearance"
        static let subtitleLanguage = "cineviet_ios_subtitle_language"
    }
}
