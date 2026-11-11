import SwiftUI

enum RhythmLanguage: String, CaseIterable {
    case system, english, simplifiedChinese

    var locale: Locale? {
        switch self {
        case .system: nil
        case .english: Locale(identifier: "en")
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        }
    }
}

enum RhythmAppearance: String, CaseIterable {
    case system, light, dark

    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: "Follow System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

@main
struct HealthTimelineApp: App {
    @Environment(\.locale) private var systemLocale
    @AppStorage("rhythmLanguage") private var language = RhythmLanguage.system
    @AppStorage("rhythmColorScheme") private var appearance = RhythmAppearance.light

    var body: some Scene {
        WindowGroup {
            HealthTimelineView(language: $language, appearance: $appearance)
                .environment(\.locale, language.locale ?? systemLocale)
                .preferredColorScheme(appearance.scheme)
                .fontDesign(.monospaced)
        }
    }
}
