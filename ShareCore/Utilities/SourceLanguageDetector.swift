//
//  SourceLanguageDetector.swift
//  ShareCore
//
//  Created by Zander on 2025/2/9.
//

import Foundation
import NaturalLanguage

/// Result of language detection with confidence scoring.
public struct LanguageDetectionResult: Sendable {
    public let language: NLLanguage?
    public let confidence: Double
    public let isReliable: Bool
}

/// Detects the source text language and resolves the target language
/// to avoid translating into the same language as the source.
public enum SourceLanguageDetector {

    // Languages matching TargetLanguageOption/SourceLanguageOption (20 languages)
    private static let supportedNLLanguages: [NLLanguage] = [
        .english, .arabic, .simplifiedChinese, .traditionalChinese,
        .dutch, .french, .german, .hindi, .indonesian, .italian,
        .japanese, .korean, .polish, .portuguese, .russian,
        .spanish, .thai, .turkish, .ukrainian, .vietnamese,
    ]

    // Prior probability hints — common languages get a slight boost
    // to improve detection accuracy for short or ambiguous text.
    private static let languageHints: [NLLanguage: Double] = [
        .english: 2.0,
        .simplifiedChinese: 1.5,
        .traditionalChinese: 0.8,
        .japanese: 0.6,
        .korean: 0.5,
        .french: 0.4, .spanish: 0.4, .italian: 0.4,
        .portuguese: 0.3, .german: 0.3, .russian: 0.3,
        .arabic: 0.2, .thai: 0.2, .vietnamese: 0.2,
        .dutch: 0.2, .polish: 0.2, .turkish: 0.2,
        .indonesian: 0.2, .hindi: 0.2, .ukrainian: 0.2,
    ]

    private static let defaultThreshold: Double = 0.3
    private static let shortTextThreshold: Double = 0.5
    private static let shortTextMaxLength = 5
    private static let maxHypotheses = 5

    /// Attempts to detect the dominant language of the given text.
    /// Returns `nil` when confidence is too low.
    public static func detectLanguage(of text: String) -> NLLanguage? {
        detectWithConfidence(of: text).language
    }

    /// Full detection with confidence scoring.
    public static func detectWithConfidence(of text: String) -> LanguageDetectionResult {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = supportedNLLanguages
        recognizer.languageHints = languageHints
        recognizer.processString(text)

        let hypotheses = recognizer.languageHypotheses(withMaximum: maxHypotheses)
        let best = hypotheses.max(by: { $0.value < $1.value })

        guard let best else {
            return LanguageDetectionResult(language: nil, confidence: 0, isReliable: false)
        }

        let effectiveThreshold = text.count <= shortTextMaxLength
            ? shortTextThreshold
            : defaultThreshold
        let isReliable = best.value >= effectiveThreshold

        if isReliable {
            return LanguageDetectionResult(
                language: best.key,
                confidence: best.value,
                isReliable: true
            )
        }

        // Fallback for very short text: if all characters are basic Latin,
        // assume English rather than returning nil (which breaks Apple Translate).
        if text.count <= shortTextMaxLength,
           text.unicodeScalars.allSatisfy({ $0.isASCII })
        {
            return LanguageDetectionResult(
                language: .english,
                confidence: best.value,
                isReliable: false
            )
        }

        return LanguageDetectionResult(
            language: nil,
            confidence: best.value,
            isReliable: false
        )
    }

    /// Resolves the target language when the source language is already known (user-pinned).
    /// Avoids NL detection — directly checks if source matches preferred target.
    public static func resolveTargetLanguage(
        forKnownSourceCode sourceCode: String,
        preferred: TargetLanguageOption
    ) -> TargetLanguageOption {
        let preferredCode = resolvedLanguageCode(for: preferred)
        guard languageCodesMatch(sourceCode, preferredCode) else {
            return preferred
        }
        // Source matches target — walk system languages for an alternative
        for identifier in Locale.preferredLanguages {
            let components = Locale.Language.Components(identifier: identifier)
            guard let langCode = components.languageCode else { continue }
            var candidateCode = langCode.identifier
            if let script = components.script {
                candidateCode += "-" + script.identifier
            }
            if !languageCodesMatch(candidateCode, sourceCode),
               let option = targetLanguageOption(for: candidateCode)
            {
                return option
            }
        }
        return preferred
    }

    /// Detects the source language and returns it as a `Locale.Language`.
    /// Useful when callers need a `Locale.Language` without importing NaturalLanguage.
    public static func detectLocaleLanguage(of text: String) -> Locale.Language? {
        guard let detected = detectLanguage(of: text) else { return nil }
        return Locale.Language(identifier: detected.rawValue)
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
