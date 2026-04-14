//
//  AppleTranslationService.swift
//  ShareCore
//
//  Created by Codex on 2025/01/05.
//

import Foundation
import SwiftUI
#if canImport(Translation)
    import Translation
#endif

/// Service for using Apple's system Translation API
/// Note: TranslationSession can only be obtained via SwiftUI's .translationTask() modifier
public final class AppleTranslationService: @unchecked Sendable {
    public static let shared = AppleTranslationService()

    /// Deployment name for Apple Translation
    public static let deploymentName = "Apple Translation"

    private init() {}

    // MARK: - Availability

    /// Check if Apple Translation is available on this device
    public var isAvailable: Bool {
        let available: Bool
        if #available(iOS 17.4, macOS 14.4, *) {
            available = true
        } else {
            available = false
        }
        Logger.debug("[AppleTranslation] isAvailable: \(available)")
        return available
    }

    /// Returns the availability status message
    public var availabilityStatus: String {
        if isAvailable {
            return NSLocalizedString("Ready to use", comment: "Apple Translation available status")
        } else {
            return NSLocalizedString("Requires iOS 17.4+ or macOS 14.4+", comment: "Apple Translation unavailable status")
        }
    }

    // MARK: - Language Availability

    /// Check whether a specific language pair is available for translation.
    @available(iOS 17.4, macOS 14.4, *)
    public func languageAvailabilityStatus(
        source: Locale.Language?,
        target: Locale.Language
    ) async -> LanguageAvailability.Status {
        let availability = LanguageAvailability()
        if let source {
            return await availability.status(from: source, to: target)
        }
        // When source is nil we rely on auto-detection; just check the target is in supported languages.
        let supported = await availability.supportedLanguages
        if supported.contains(where: { $0.minimalIdentifier == target.minimalIdentifier }) {
            return .supported
        }
        return .unsupported
    }

    // MARK: - Installed Languages

    /// Returns the set of `TargetLanguageOption`s whose translation language packs
    /// are installed on this device (checked as pairs with English).
    @available(iOS 17.4, macOS 14.4, *)
    public func refreshInstalledLanguages() async -> Set<TargetLanguageOption> {
        let availability = LanguageAvailability()
        let english = Locale.Language(identifier: "en")
        var installed: Set<TargetLanguageOption> = []

        for option in TargetLanguageOption.allCases where option != .appLanguage {
            let target = option.localeLanguage
            // Check en → target
            let forwardStatus = await availability.status(from: english, to: target)
            if forwardStatus == .installed {
                installed.insert(option)
            }
            // Check target → en (covers bidirectional use)
            let reverseStatus = await availability.status(from: target, to: english)
            if reverseStatus == .installed {
                installed.insert(option)
                installed.insert(.english)
            }
        }

        Logger.debug("[AppleTranslation] refreshInstalledLanguages: \(installed.map(\.rawValue))")
        return installed
    }

    // MARK: - Translation

    /// Translate a single text string using the provided TranslationSession.
    @available(iOS 17.4, macOS 14.4, *)
    public func translate(
        text: String,
        using session: TranslationSession
    ) async throws -> ModelExecutionResult {
        let start = Date()
        Logger.debug("[AppleTranslation] translate called, text length: \(text.count)")

        // prepareTranslation() triggers the system download UI if the language pack
        // is not yet installed (.supported status). No-op if already installed (.installed).
        try await session.prepareTranslation()
        // Notify the host app that language download is done and the auxiliary window can be hidden.
        NotificationCenter.default.post(name: .appleTranslationPrepareCompleted, object: nil)

        let response = try await session.translate(text)
        let duration = Date().timeIntervalSince(start)

        Logger.debug("[AppleTranslation] translate success, duration: \(duration)s")
        return ModelExecutionResult(
            modelID: ModelConfig.appleTranslateID,
            duration: duration,
            response: .success(response.targetText)
        )
    }

    /// Translate text as sentence pairs using the provided TranslationSession.
    @available(iOS 17.4, macOS 14.4, *)
    public func translateSentences(
        text: String,
        using session: TranslationSession
    ) async throws -> ModelExecutionResult {
        let start = Date()

        // prepareTranslation() triggers the system download UI if needed.
        try await session.prepareTranslation()
        NotificationCenter.default.post(name: .appleTranslationPrepareCompleted, object: nil)

        let sentences = splitIntoSentences(text)
        Logger.debug("[AppleTranslation] translateSentences: \(sentences.count) sentences")

        let requests = sentences.enumerated().map { index, sentence in
            TranslationSession.Request(sourceText: sentence, clientIdentifier: "\(index)")
        }

        let responses = try await session.translations(from: requests)

        // Map responses back by clientIdentifier to maintain order.
        var translatedByIndex: [Int: String] = [:]
        for response in responses {
            if let id = response.clientIdentifier, let index = Int(id) {
                translatedByIndex[index] = response.targetText
            }
        }

        var pairs: [SentencePair] = []
        for (index, original) in sentences.enumerated() {
            let translation = translatedByIndex[index] ?? ""
            pairs.append(SentencePair(original: original, translation: translation))
        }

        let duration = Date().timeIntervalSince(start)
        Logger.debug("[AppleTranslation] translateSentences success, duration: \(duration)s")
        return ModelExecutionResult(
            modelID: ModelConfig.appleTranslateID,
            duration: duration,
            response: .success(pairs.map(\.translation).joined(separator: "\n")),
            sentencePairs: pairs
        )
    }

    // MARK: - Sentence Splitting (Public utility)

    /// Split text into sentences for translation
    public func splitIntoSentences(_ text: String) -> [String] {
        Logger.debug("[AppleTranslation] splitIntoSentences called, text length: \(text.count)")
        var sentences: [String] = []

        let tagger = NSLinguisticTagger(tagSchemes: [.tokenType], options: 0)
        tagger.string = text

        let range = NSRange(location: 0, length: text.utf16.count)

        tagger.enumerateTags(in: range, unit: .sentence, scheme: .tokenType, options: []) { _, tokenRange, _ in
            if let swiftRange = Range(tokenRange, in: text) {
                let sentence = String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty {
                    sentences.append(sentence)
                }
            }
        }

        // Fallback if no sentences found
        if sentences.isEmpty, !text.isEmpty {
            // Simple fallback: split by common sentence terminators
            let pattern = "(?<=[.!?。！？])\\s+"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let splits = regex.stringByReplacingMatches(
                    in: text,
                    options: [],
                    range: range,
                    withTemplate: "\n<<<SPLIT>>>\n"
                ).components(separatedBy: "<<<SPLIT>>>")

                sentences = splits.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }

            // If still empty, treat whole text as one sentence
            if sentences.isEmpty {
                sentences = [text.trimmingCharacters(in: .whitespacesAndNewlines)]
            }
        }

        Logger.debug("[AppleTranslation] splitIntoSentences result: \(sentences.count) sentences")
        return sentences
    }
}

// MARK: - Local Provider Errors

public enum LocalProviderError: LocalizedError {
    case notAvailable(String)
    case translationFailed(String)
    case unsupportedAction
    case unsupportedLanguagePair

    public var errorDescription: String? {
        switch self {
        case let .notAvailable(reason):
            return reason
        case let .translationFailed(reason):
            return reason
        case .unsupportedAction:
            return NSLocalizedString("This action is not supported by the selected provider", comment: "Unsupported action error")
        case .unsupportedLanguagePair:
            return NSLocalizedString("Apple Translate does not support this language pair", comment: "Unsupported language pair error")
        }
    }
}

// MARK: - SourceLanguageOption Extension

public extension SourceLanguageOption {
    /// Convert to optional Locale.Language for Translation API (nil for .auto)
    var localeLanguage: Locale.Language? {
        switch self {
        case .auto:
            return nil
        default:
            return Locale.Language(identifier: rawValue)
        }
    }
}

// MARK: - TargetLanguageOption Extension

public extension TargetLanguageOption {
    /// Convert to Locale.Language for Translation API
    var localeLanguage: Locale.Language {
        switch self {
        case .appLanguage:
            return Locale.Language(identifier: TargetLanguageOption.appLanguageIdentifier)
        case .simplifiedChinese:
            return Locale.Language(identifier: "zh-Hans")
        case .english:
            return Locale.Language(identifier: "en")
        case .japanese:
            return Locale.Language(identifier: "ja")
        case .korean:
            return Locale.Language(identifier: "ko")
        case .french:
            return Locale.Language(identifier: "fr")
        case .german:
            return Locale.Language(identifier: "de")
        case .spanish:
            return Locale.Language(identifier: "es")
        }
    }
}

#if os(macOS)
    public extension Notification.Name {
        /// Posted after `TranslationSession.prepareTranslation()` completes (language pack
        /// downloaded or already installed). The macOS host app uses this to hide the
        /// auxiliary translation window after the download sheet is dismissed.
        static let appleTranslationPrepareCompleted = Notification.Name("appleTranslationPrepareCompleted")
    }
#endif
