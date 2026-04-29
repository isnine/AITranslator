//
//  SourceLanguageDetector.swift
//  ShareCore
//
//  Created by Zander on 2025/2/9.
//

import Foundation
import NaturalLanguage
import os

private let logger = os.Logger(subsystem: "com.zanderwang.AITranslator", category: "SourceLanguageDetector")

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
    private static let shortTextMaxLength = 10
    private static let shortTextMaxWords = 3
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
        let hypothesesDesc = hypotheses
            .sorted { $0.value > $1.value }
            .map { "\($0.key.rawValue):\(String(format: "%.3f", $0.value))" }
            .joined(separator: ", ")

        guard let best else {
            logger.debug("detect text='\(text, privacy: .public)' → no hypotheses")
            return LanguageDetectionResult(language: nil, confidence: 0, isReliable: false)
        }

        let isShort = isShortText(text)
        let effectiveThreshold = isShort ? shortTextThreshold : defaultThreshold
        let isReliable = best.value >= effectiveThreshold

        if isReliable {
            let corrected = correctChineseScript(best.key)
            logger.debug("detect text='\(text, privacy: .public)' hypotheses=[\(hypothesesDesc, privacy: .public)] short=\(isShort, privacy: .public) → '\(corrected.rawValue, privacy: .public)' (confidence \(best.value, privacy: .public) ≥ \(effectiveThreshold, privacy: .public))")
            return LanguageDetectionResult(
                language: corrected,
                confidence: best.value,
                isReliable: true
            )
        }

        logger.debug("detect text='\(text, privacy: .public)' hypotheses=[\(hypothesesDesc, privacy: .public)] short=\(isShort, privacy: .public) → unreliable (top \(best.value, privacy: .public) < \(effectiveThreshold, privacy: .public))")
        return LanguageDetectionResult(
            language: nil,
            confidence: best.value,
            isReliable: false
        )
    }

    /// Detects the source language and returns it as a `Locale.Language`.
    /// Useful when callers need a `Locale.Language` without importing NaturalLanguage.
    public static func detectLocaleLanguage(of text: String) -> Locale.Language? {
        guard let detected = detectLanguage(of: text) else { return nil }
        return Locale.Language(identifier: detected.rawValue)
    }

    /// Detects source language with NLLanguageRecognizer constrained to the given candidates only.
    /// Used in Match mode to improve short-text accuracy.
    public static func detectLocaleLanguageConstrained(
        of text: String,
        candidateCodes: [String]
    ) -> Locale.Language? {
        let constraints = candidateCodes.compactMap { nlLanguage(forCode: $0) }
        guard !constraints.isEmpty else { return detectLocaleLanguage(of: text) }

        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = constraints
        recognizer.languageHints = languageHints.filter { constraints.contains($0.key) }
        recognizer.processString(text)

        let hypotheses = recognizer.languageHypotheses(withMaximum: maxHypotheses)
        let sorted = hypotheses.sorted { $0.value > $1.value }
        let isShort = isShortText(text)
        let threshold = isShort ? shortTextThreshold : defaultThreshold

        guard let top = sorted.first, top.value >= threshold else { return nil }
        let corrected = correctChineseScript(top.key)
        return Locale.Language(identifier: corrected.rawValue)
    }

    /// Picks the best target from `candidates` that differs from `sourceCode`.
    /// Priority: iterate candidates in order (app language first, then preferred, then English).
    public static func resolveMatchTarget(
        sourceCode: String?,
        candidates: [TargetLanguageOption]
    ) -> TargetLanguageOption {
        guard let sourceCode, !candidates.isEmpty else {
            return candidates.first ?? .english
        }
        for candidate in candidates {
            if !languageCodesMatch(sourceCode, candidate.rawValue) {
                return candidate
            }
        }
        return candidates.first ?? .english
    }
    ///
    /// Returns the BCP 47 source language code (e.g. "en", "zh-Hans") that auto-detection
    /// resolves to, given the user's target language and preferred language list.
    ///
    /// - Parameters:
    ///   - text: Source text.
    ///   - targetCode: The user-selected target language code (used to bias detection
    ///     away from source == target).
    ///   - preferredLanguages: The user's system language list (for Chinese script correction).
    ///     Defaults to `Locale.preferredLanguages`.
    /// - Returns: A BCP 47 code, or `nil` when detection is inconclusive.
    public static func resolveAutoSourceCode(
        text: String,
        targetCode: String?,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String? {
        guard let targetCode, !targetCode.isEmpty else {
            guard let detected = detectLanguage(of: text) else { return nil }
            let corrected = correctChineseScript(detected, preferredLanguages: preferredLanguages)
            return corrected.rawValue
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = supportedNLLanguages
        recognizer.languageHints = languageHints
        recognizer.processString(text)

        let hypotheses = recognizer.languageHypotheses(withMaximum: maxHypotheses)
        guard !hypotheses.isEmpty else { return nil }

        let isShort = isShortText(text)
        let threshold = isShort ? shortTextThreshold : defaultThreshold
        let minimumExclusionConfidence = 0.15
        let excludedTopRelativeRatio = 0.3

        let sorted = hypotheses.sorted { $0.value > $1.value }
        let excludedTopConfidence = sorted.first { languageCodesMatch($0.key.rawValue, targetCode) }?.value ?? 0
        let relativeFloor = excludedTopConfidence * excludedTopRelativeRatio

        for (lang, confidence) in sorted {
            if languageCodesMatch(lang.rawValue, targetCode) { continue }
            if confidence < minimumExclusionConfidence { break }
            if confidence < relativeFloor { break }
            let corrected = correctChineseScript(lang, preferredLanguages: preferredLanguages)
            return corrected.rawValue
        }

        if let top = sorted.first, top.value >= threshold {
            let corrected = correctChineseScript(top.key, preferredLanguages: preferredLanguages)
            return corrected.rawValue
        }
        return nil
    }

    /// Like `detectLocaleLanguage(of:)`, but skips any hypothesis whose base language
    /// matches `targetCode`. Delegates to `resolveAutoSourceCode` for the core logic;
    /// adds full logging.
    public static func detectLocaleLanguage(
        of text: String,
        excludingTargetCode targetCode: String?
    ) -> Locale.Language? {
        guard let targetCode, !targetCode.isEmpty else {
            return detectLocaleLanguage(of: text)
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = supportedNLLanguages
        recognizer.languageHints = languageHints
        recognizer.processString(text)

        let hypotheses = recognizer.languageHypotheses(withMaximum: maxHypotheses)
        guard !hypotheses.isEmpty else {
            logger.debug("detectExcluding(target=\(targetCode, privacy: .public)) text='\(text, privacy: .public)' → no hypotheses")
            return nil
        }

        let isShort = isShortText(text)
        let threshold = isShort ? shortTextThreshold : defaultThreshold
        let minimumExclusionConfidence = 0.15
        let excludedTopRelativeRatio = 0.3

        let sorted = hypotheses.sorted { $0.value > $1.value }
        let hypothesesDesc = sorted
            .map { "\($0.key.rawValue):\(String(format: "%.3f", $0.value))" }
            .joined(separator: ", ")
        let excludedTopConfidence = sorted.first { languageCodesMatch($0.key.rawValue, targetCode) }?.value ?? 0
        let relativeFloor = excludedTopConfidence * excludedTopRelativeRatio

        for (lang, confidence) in sorted {
            if languageCodesMatch(lang.rawValue, targetCode) { continue }
            if confidence < minimumExclusionConfidence {
                logger.debug("detectExcluding(target=\(targetCode, privacy: .public)) text='\(text, privacy: .public)' hypotheses=[\(hypothesesDesc, privacy: .public)] → '\(lang.rawValue, privacy: .public)' rejected (confidence \(confidence, privacy: .public) < absolute floor \(minimumExclusionConfidence, privacy: .public))")
                break
            }
            if confidence < relativeFloor {
                logger.debug("detectExcluding(target=\(targetCode, privacy: .public)) text='\(text, privacy: .public)' hypotheses=[\(hypothesesDesc, privacy: .public)] → '\(lang.rawValue, privacy: .public)' rejected (confidence \(confidence, privacy: .public) < \(excludedTopRelativeRatio, privacy: .public) × excluded top \(excludedTopConfidence, privacy: .public) = \(relativeFloor, privacy: .public))")
                break
            }
            let corrected = correctChineseScript(lang)
            logger.debug("detectExcluding(target=\(targetCode, privacy: .public)) text='\(text, privacy: .public)' hypotheses=[\(hypothesesDesc, privacy: .public)] → picked '\(corrected.rawValue, privacy: .public)' (confidence \(confidence, privacy: .public))")
            return Locale.Language(identifier: corrected.rawValue)
        }

        // No non-target candidate qualifies — return the unfiltered top hypothesis if reliable.
        if let top = sorted.first, top.value >= threshold {
            let corrected = correctChineseScript(top.key)
            logger.debug("detectExcluding(target=\(targetCode, privacy: .public)) text='\(text, privacy: .public)' hypotheses=[\(hypothesesDesc, privacy: .public)] → no qualifying non-target, falling back to top '\(corrected.rawValue, privacy: .public)' (confidence \(top.value, privacy: .public))")
            return Locale.Language(identifier: corrected.rawValue)
        }
        logger.debug("detectExcluding(target=\(targetCode, privacy: .public)) text='\(text, privacy: .public)' hypotheses=[\(hypothesesDesc, privacy: .public)] → no qualifying candidate and top below threshold \(threshold, privacy: .public), returning nil")
        return nil
    }

    /// Fallback chain when source detection is inconclusive:
    /// 1. user-pinned `sourceLanguage` (if not `.auto`)
    /// 2. first supported entry in `Locale.preferredLanguages`
    /// 3. English
    public static func fallbackSourceLanguage(
        userPreference: SourceLanguageOption? = nil
    ) -> Locale.Language {
        let preference = userPreference ?? AppPreferences.shared.sourceLanguage
        if preference != .auto {
            return Locale.Language(identifier: preference.rawValue)
        }
        for identifier in Locale.preferredLanguages {
            let components = Locale.Language.Components(identifier: identifier)
            guard let langCode = components.languageCode else { continue }
            var candidate = langCode.identifier
            if let script = components.script {
                candidate += "-" + script.identifier
            }
            if SourceLanguageOption(rawValue: candidate) != nil
                || SourceLanguageOption(rawValue: langCode.identifier) != nil
            {
                return Locale.Language(identifier: candidate)
            }
        }
        return Locale.Language(identifier: "en")
    }

    /// Returns true when two BCP 47 codes refer to the same translation language
    /// (e.g. "en" == "en-US" == "en-Latn", "zh-Hans" treated as same as "zh-Hant" per detector design).
    static func languagesAreSame(_ a: String, _ b: String) -> Bool {
        languageCodesMatch(a, b)
    }

    // MARK: - Private Helpers

    /// Reconciles zh-Hans / zh-Hant detection against the user's
    /// `preferredLanguages`. NLLanguageRecognizer cannot reliably
    /// distinguish scripts for short Han text like "你好"; if the detected
    /// script is absent from the user's preferred list but the other script
    /// is present, swap to what the user actually has.
    static func correctChineseScript(
        _ detected: NLLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> NLLanguage {
        guard detected == .simplifiedChinese || detected == .traditionalChinese else {
            return detected
        }
        var hasHans = false
        var hasHant = false
        for identifier in preferredLanguages {
            let components = Locale.Language.Components(identifier: identifier)
            guard components.languageCode?.identifier == "zh" else { continue }
            switch components.script?.identifier {
            case "Hans": hasHans = true
            case "Hant": hasHant = true
            default: break
            }
        }
        if detected == .traditionalChinese, !hasHant, hasHans {
            return .simplifiedChinese
        }
        if detected == .simplifiedChinese, !hasHans, hasHant {
            return .traditionalChinese
        }
        return detected
    }

    /// Treats text as "short" when either the character count or the
    /// word count is small. Word count uses Unicode word boundaries so
    /// that languages without spaces (CJK) are not mis-classified.
    private static func isShortText(_ text: String) -> Bool {
        if text.count <= shortTextMaxLength { return true }
        var wordCount = 0
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.byWords, .localized]
        ) { _, _, _, stop in
            wordCount += 1
            if wordCount > shortTextMaxWords {
                stop = true
            }
        }
        return wordCount <= shortTextMaxWords
    }

    /// Compares two language codes, matching on the base language
    /// (e.g. "zh-Hans" matches "zh-Hant", "en-US" matches "en", "en" matches "en-Latn").
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

        let aComp = Locale.Language.Components(identifier: a)
        let bComp = Locale.Language.Components(identifier: b)
        guard let aLang = aComp.languageCode?.identifier,
              let bLang = bComp.languageCode?.identifier,
              aLang == bLang
        else {
            return false
        }

        // Both sides carry a script (e.g. zh-Hans vs zh-Hant) — treat as same language
        // because NLLanguageRecognizer cannot reliably distinguish scripts for short text.
        if aComp.script != nil, bComp.script != nil { return true }

        // One side bare, the other has a script: only collapse when the script is
        // the language's *default* script (e.g. "en" vs "en-Latn"). For languages
        // with multiple meaningful scripts (zh, sr, mn, az, …) this still distinguishes.
        let onlyScript = aComp.script?.identifier ?? bComp.script?.identifier
        if let onlyScript, onlyScript == defaultScript(forLanguageCode: aLang) {
            return true
        }

        return false
    }

    /// Default script for a language code, used to ignore redundant script tags
    /// (e.g. "en-Latn" is just "en"). Only languages whose detector output may
    /// include a script tag need to be listed here.
    private static func defaultScript(forLanguageCode code: String) -> String? {
        switch code {
        case "en", "fr", "de", "es", "it", "pt", "nl", "pl", "tr", "id", "vi":
            return "Latn"
        case "ru", "uk":
            return "Cyrl"
        case "ar":
            return "Arab"
        case "ja":
            return "Jpan"
        case "ko":
            return "Kore"
        case "th":
            return "Thai"
        case "hi":
            return "Deva"
        default:
            return nil
        }
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

    /// Maps a BCP 47 code to `NLLanguage` by matching against `supportedNLLanguages`.
    private static func nlLanguage(forCode code: String) -> NLLanguage? {
        let nl = NLLanguage(rawValue: code)
        if supportedNLLanguages.contains(nl) { return nl }
        let base = baseLanguage(code)
        let nlBase = NLLanguage(rawValue: base)
        if supportedNLLanguages.contains(nlBase) { return nlBase }
        return nil
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
