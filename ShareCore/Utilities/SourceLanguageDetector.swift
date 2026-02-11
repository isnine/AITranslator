//
//  SourceLanguageDetector.swift
//  ShareCore
//
//  Created by Zander on 2025/2/9.
//

import Foundation
import NaturalLanguage

/// Detects the source text language and resolves the target language
/// to avoid translating into the same language as the source.
public enum SourceLanguageDetector {

    /// Attempts to detect the dominant language of the given text.
    /// Returns `nil` when confidence is too low.
    public static func detectLanguage(of text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage
    }

    /// Returns the best target language option for the given source text.
    ///
    /// When the detected source language matches the user's preferred target,
    /// the method walks `Locale.preferredLanguages` to find the next best
    /// language that differs from the source. Falls back to the preferred
    /// target if detection is inconclusive or no alternative is found.
    public static func resolveTargetLanguage(
        for text: String,
        preferred: TargetLanguageOption
    ) -> TargetLanguageOption {
        guard let detected = detectLanguage(of: text) else {
            return preferred
        }

        let detectedCode = detected.rawValue // e.g. "en", "zh-Hans", "ja"
        let preferredCode = resolvedLanguageCode(for: preferred)

        // If the source language doesn't match the preferred target, keep it
        guard languageCodesMatch(detectedCode, preferredCode) else {
            return preferred
        }

        // Source matches target — find an alternative from the user's system languages
        for identifier in Locale.preferredLanguages {
            let components = Locale.Language.Components(identifier: identifier)
            guard let langCode = components.languageCode else { continue }

            var candidateCode = langCode.identifier
            if let script = components.script {
                candidateCode += "-" + script.identifier
            }

            if !languageCodesMatch(candidateCode, detectedCode),
               let option = targetLanguageOption(for: candidateCode)
            {
                return option
            }
        }

        // No suitable alternative found — keep original preference
        return preferred
    }

    // MARK: - Private Helpers

    /// Resolves the underlying language code for a `TargetLanguageOption`,
    /// handling the `.appLanguage` case.
    private static func resolvedLanguageCode(for option: TargetLanguageOption) -> String {
        switch option {
        case .appLanguage:
            return TargetLanguageOption.appLanguageIdentifier
        default:
            return option.rawValue
        }
    }

    /// Compares two language codes, matching on the base language
    /// (e.g. "zh-Hans" matches "zh-Hant", "en-US" matches "en").
    ///
    /// Script variants of the same language (e.g. Simplified vs Traditional Chinese)
    /// are treated as matching because NLLanguageRecognizer cannot reliably distinguish
    /// scripts for short or script-ambiguous text like "你好".
    private static func languageCodesMatch(_ a: String, _ b: String) -> Bool {
        // Exact match
        if a == b { return true }

        // Compare base language codes (language + script)
        let aBase = baseLanguage(a)
        let bBase = baseLanguage(b)
        if aBase == bBase { return true }

        // Fall back to language-only comparison so that script variants
        // (zh-Hans vs zh-Hant) are still considered the same language.
        let aLang = Locale.Language.Components(identifier: a).languageCode?.identifier
        let bLang = Locale.Language.Components(identifier: b).languageCode?.identifier
        if let aLang, let bLang, aLang == bLang { return true }

        return false
    }

    /// Extracts the base language (language + script if present) from an identifier.
    /// "en-US" → "en", "zh-Hans-CN" → "zh-Hans", "zh-Hans" → "zh-Hans"
    private static func baseLanguage(_ identifier: String) -> String {
        let components = Locale.Language.Components(identifier: identifier)
        guard let langCode = components.languageCode else { return identifier }
        var base = langCode.identifier
        if let script = components.script {
            base += "-" + script.identifier
        }
        return base
    }

    /// Maps a language code to the corresponding `TargetLanguageOption`, if one exists.
    private static func targetLanguageOption(for code: String) -> TargetLanguageOption? {
        let base = baseLanguage(code)
        for option in TargetLanguageOption.allCases where option != .appLanguage {
            if option.rawValue == base {
                return option
            }
            // Also match base language without script (e.g. "en-US" → "en")
            if baseLanguage(option.rawValue) == baseLanguage(base) {
                return option
            }
        }
        return nil
    }
}
