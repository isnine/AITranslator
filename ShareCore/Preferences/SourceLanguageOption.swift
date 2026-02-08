//
//  SourceLanguageOption.swift
//  ShareCore
//

import Foundation

public enum SourceLanguageOption: String, CaseIterable, Identifiable, Codable {
    case auto = "auto"
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"

    public static let storageKey = "settings.sourceLanguageCode"

    public var id: String { rawValue }

    public static var selectionOptions: [SourceLanguageOption] {
        [
            .auto,
            .english,
            .simplifiedChinese,
            .japanese,
            .korean,
            .french,
            .german,
            .spanish,
        ]
    }

    /// Display name shown in the language switcher (short).
    public var displayName: String {
        switch self {
        case .auto:
            return "Auto"
        default:
            return nativeName
        }
    }

    /// Primary label used in the picker list.
    public var primaryLabel: String {
        switch self {
        case .auto:
            return "Auto (Detect)"
        default:
            return nativeName
        }
    }

    /// Secondary label used in the picker list.
    public var secondaryLabel: String {
        switch self {
        case .auto:
            return "Automatically detect input language"
        default:
            return englishName
        }
    }

    /// Descriptor injected into prompts.
    /// Returns `nil` when set to `.auto` so the caller knows not to inject.
    public var promptDescriptor: String? {
        switch self {
        case .auto:
            return nil
        default:
            let native = nativeName
            let english = englishName
            guard native != english else { return native }
            return "\(native) (\(english))"
        }
    }

    // MARK: - Private helpers

    public var nativeName: String {
        name(in: Locale(identifier: rawValue))
    }

    public var englishName: String {
        name(in: Locale(identifier: "en"))
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

    private func resolvedIdentifier() -> String {
        var components = Locale.Components(identifier: rawValue)
        if components.languageComponents.languageCode == nil {
            components.languageComponents.languageCode = Locale.LanguageCode(rawValue)
        }
        return Locale(components: components).identifier
    }
}
