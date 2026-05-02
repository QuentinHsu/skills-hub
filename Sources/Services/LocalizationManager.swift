import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case en
    case zhHans = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: "English"
        case .zhHans: "简体中文"
        }
    }

    var lprojName: String {
        switch self {
        case .en: "en"
        case .zhHans: "zh-hans"
        }
    }

    static func fromSystem() -> AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("zh") { return .zhHans }
        return .en
    }
}

@Observable
@MainActor
final class LocalizationManager {
    var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "appLanguage")
        }
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: "appLanguage"),
           let lang = AppLanguage(rawValue: saved)
        {
            self.currentLanguage = lang
        } else {
            self.currentLanguage = AppLanguage.fromSystem()
        }
    }

    nonisolated static func currentLang() -> AppLanguage {
        if let saved = UserDefaults.standard.string(forKey: "appLanguage"),
           let lang = AppLanguage(rawValue: saved)
        {
            return lang
        }
        return AppLanguage.fromSystem()
    }

    nonisolated static func t(_ key: String, lang: AppLanguage) -> String {
        let bundle = loadBundle(for: lang)
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    nonisolated static func localize(_ key: String) -> String {
        let lang = currentLang()
        return t(key, lang: lang)
    }

    nonisolated private static func loadBundle(for lang: AppLanguage) -> Bundle {
        let resourceBundle = AppResourceBundle.bundle
        guard let lprojURL = resourceBundle.url(forResource: lang.lprojName, withExtension: "lproj"),
              let bundle = Bundle(url: lprojURL)
        else {
            return resourceBundle
        }
        return bundle
    }
}

// MARK: - Localized Text Helpers

enum L {
    @MainActor
    private static func format(_ key: String, _ args: [any CVarArg], using lm: LocalizationManager) -> String {
        let lang = lm.currentLanguage
        let template = LocalizationManager.t(key, lang: lang)
        if args.isEmpty {
            return template
        }
        return String(format: template, arguments: args)
    }

    /// Localized `Text` — pass `lm` from `@Environment` so SwiftUI tracks the dependency.
    @MainActor
    static func text(_ key: String, _ args: any CVarArg..., using lm: LocalizationManager) -> Text {
        Text(format(key, args, using: lm))
    }

    /// Localized `String` — pass `lm` from `@Environment` so SwiftUI tracks the dependency.
    @MainActor
    static func string(_ key: String, _ args: any CVarArg..., using lm: LocalizationManager) -> String {
        format(key, args, using: lm)
    }

    @MainActor
    static func label(_ key: String, systemImage: String, _ args: any CVarArg..., using lm: LocalizationManager) -> some View {
        Label(format(key, args, using: lm), systemImage: systemImage)
    }
}
