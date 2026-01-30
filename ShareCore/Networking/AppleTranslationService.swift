//
//  AppleTranslationService.swift
//  ShareCore
//
//  Created by Codex on 2025/01/05.
//

import Foundation
import SwiftUI

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

    public var errorDescription: String? {
        switch self {
        case let .notAvailable(reason):
            return reason
        case let .translationFailed(reason):
            return reason
        case .unsupportedAction:
            return NSLocalizedString("This action is not supported by the selected provider", comment: "Unsupported action error")
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
