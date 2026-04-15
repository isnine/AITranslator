//
//  SourceLanguageOption.swift
//  ShareCore
//

import Foundation

public enum SourceLanguageOption: String, CaseIterable, Identifiable, Codable {
    case auto = "auto"
    case english = "en"
    case arabic = "ar"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case dutch = "nl"
    case french = "fr"
    case german = "de"
    case hindi = "hi"
    case indonesian = "id"
    case italian = "it"
    case japanese = "ja"
    case korean = "ko"
    case polish = "pl"
    case portugueseBrazil = "pt-BR"
    case russian = "ru"
    case spanish = "es"
    case thai = "th"
    case turkish = "tr"
    case ukrainian = "uk"
    case vietnamese = "vi"

    public static let storageKey = "settings.sourceLanguageCode"

    public var id: String { rawValue }

    public var primaryLabel: String {
        switch self {
        case .auto:
            return String(localized: "Auto")
        default:
            return nativeName
        }
    }

    public var secondaryLabel: String {
        switch self {
        case .auto:
            return String(localized: "Detect automatically")
        default:
            return englishName
        }
    }

    public var nativeName: String {
        guard self != .auto else { return "Auto" }
        let locale = Locale(identifier: rawValue)
        return locale.localizedString(forIdentifier: rawValue) ?? rawValue
    }

    public var englishName: String {
        guard self != .auto else { return "Auto" }
        let english = Locale(identifier: "en")
        return english.localizedString(forIdentifier: rawValue) ?? rawValue
    }
}
