//
//  PromptSubstitution.swift
//  ShareCore
//

import Foundation

/// Pure-function prompt placeholder substitution.
///
/// Replaces both `{placeholder}` and `{{placeholder}}` variants.
/// Double-brace forms are replaced first so that `{{x}}` is not
/// partially matched by the single-brace pass.
public enum PromptSubstitution {
    /// Supported placeholders:
    /// - `{text}` / `{{text}}`                     - user input text
    /// - `{targetLanguage}` / `{{targetLanguage}}` - target language descriptor
    /// - `{sourceLanguage}` / `{{sourceLanguage}}` - source language descriptor (empty when Auto)
    public static func substitute(
        prompt: String,
        text: String,
        targetLanguage: String,
        sourceLanguage: String
    ) -> String {
        var result = prompt

        // Double-brace first to avoid partial match
        result = result.replacingOccurrences(of: "{{targetLanguage}}", with: targetLanguage)
        result = result.replacingOccurrences(of: "{targetLanguage}", with: targetLanguage)

        result = result.replacingOccurrences(of: "{{sourceLanguage}}", with: sourceLanguage)
        result = result.replacingOccurrences(of: "{sourceLanguage}", with: sourceLanguage)

        result = result.replacingOccurrences(of: "{{text}}", with: text)
        result = result.replacingOccurrences(of: "{text}", with: text)

        return result
    }

    /// Whether the original prompt template contains a `{text}` or `{{text}}` placeholder.
    public static func containsTextPlaceholder(_ prompt: String) -> Bool {
        prompt.contains("{text}") || prompt.contains("{{text}}")
    }
}
