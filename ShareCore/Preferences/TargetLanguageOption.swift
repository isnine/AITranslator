//
//  TargetLanguageOption.swift
//  ShareCore
//
//  Created by Codex on 2025/10/27.
//

import Foundation

public enum TargetLanguageOption: String, CaseIterable, Identifiable, Codable {
    case appLanguage = "app-language"
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"

    public static let storageKey = "settings.targetLanguageCode"

    public var id: String { rawValue }

    public static var selectionOptions: [TargetLanguageOption] {
        [
            .appLanguage,
            .english,
            .simplifiedChinese,
            .japanese,
            .korean,
            .french,
            .german,
            .spanish,
        ]
    }

    public var nativeName: String {
        name(in: Locale(identifier: baseIdentifier))
    }

    public var localizedName: String {
        name(in: Locale(identifier: TargetLanguageOption.appLanguageIdentifier))
    }

    public var englishName: String {
        name(in: Locale(identifier: "en"))
    }

    public var primaryLabel: String {
        switch self {
        case .appLanguage:
            return "Match App Language"
        default:
            return nativeName
        }
    }

    public var secondaryLabel: String {
        switch self {
        case .appLanguage:
            let english = TargetLanguageOption.appLanguageEnglishName
            return english.isEmpty ? "Use the current app language" : english
        default:
            return englishName
        }
    }

    public var resolvedLocale: Locale {
        Locale(identifier: resolvedIdentifier())
    }

    public static var appLanguageIdentifier: String {
        if let preferred = Bundle.main.preferredLocalizations.first, !preferred.isEmpty {
            return preferred
        }
        if let systemPreferred = Locale.preferredLanguages.first, !systemPreferred.isEmpty {
            return systemPreferred
        }
        return Locale.autoupdatingCurrent.identifier
    }

    public static var appLanguageEnglishName: String {
        let englishLocale = Locale(identifier: "en")
        let identifier = appLanguageIdentifier
        if let localized = englishLocale.localizedString(forIdentifier: identifier) {
            return localized
        }
        let components = Locale.Components(identifier: identifier)
        if let languageCode = components.languageComponents.languageCode,
           let english = englishLocale.localizedString(forLanguageCode: languageCode.identifier)
        {
            return english
        }
        return identifier
    }

    public var promptDescriptor: String {
        let native = nativeName
        let english = englishName
        guard native != english else { return native }
        return "\(native) (\(english))"
    }

    private var baseIdentifier: String {
        switch self {
        case .appLanguage:
            return TargetLanguageOption.appLanguageIdentifier
        default:
            return rawValue
        }
    }

    private func resolvedIdentifier() -> String {
        var components = Locale.Components(identifier: baseIdentifier)
        if components.languageComponents.languageCode == nil {
            components.languageComponents.languageCode = Locale.LanguageCode(baseIdentifier)
        }
        return Locale(components: components).identifier
    }

    private func name(in locale: Locale) -> String {
        let identifier = resolvedIdentifier()
        if let localized = locale.localizedString(forIdentifier: identifier), !localized.isEmpty {
            return localized
        }

        let components = Locale.Components(identifier: identifier)
        guard let languageCode = components.languageComponents.languageCode else {
            return identifier
        }

        var name = locale.localizedString(forLanguageCode: languageCode.identifier) ?? identifier

        if let scriptCode = components.languageComponents.script,
           let scriptName = locale.localizedString(forScriptCode: scriptCode.identifier),
           !scriptName.isEmpty
        {
            name += " (\(scriptName))"
        }

        return name
    }
}
