//
//  OutputType.swift
//  ShareCore
//
//  Created by AI Assistant on 2025/12/31.
//

import Foundation

/// Defines how the LLM response should be processed and displayed.
public enum OutputType: String, Codable, CaseIterable, Sendable {
    /// Plain text output (default)
    case plain

    /// Diff comparison display (original strikethrough + new highlight)
    case diff

    /// Sentence-by-sentence translation pairs
    case sentencePairs

    /// Grammar check with revised text + explanations
    case grammarCheck

    /// Translation output — marks the action as a translation task
    case translate

    /// Whether to show diff comparison in the UI
    public var showsDiff: Bool {
        switch self {
        case .diff, .grammarCheck:
            return true
        case .plain, .sentencePairs, .translate:
            return false
        }
    }

    /// Display mode for the result
    public var displayMode: ActionConfig.DisplayMode {
        switch self {
        case .sentencePairs:
            return .sentencePairs
        case .plain, .diff, .grammarCheck, .translate:
            return .standard
        }
    }

    /// Built-in structured output configuration, if applicable
    public var structuredOutput: ActionConfig.StructuredOutputConfig? {
        switch self {
        case .sentencePairs:
            return .sentencePairs
        case .grammarCheck:
            return .grammarCheck
        case .plain, .diff, .translate:
            return nil
        }
    }

    /// SF Symbol name for this output type
    public var systemImageName: String {
        switch self {
        case .plain:
            return "doc.text"
        case .diff:
            return "arrow.left.arrow.right"
        case .sentencePairs:
            return "text.alignleft"
        case .grammarCheck:
            return "checkmark.seal"
        case .translate:
            return "globe"
        }
    }

    /// Localized display name for this output type
    public var displayName: String {
        switch self {
        case .plain:
            return String(localized: "Plain Text", comment: "Output type name")
        case .diff:
            return String(localized: "Show Diff", comment: "Output type name")
        case .sentencePairs:
            return String(localized: "Sentence Pairs", comment: "Output type name")
        case .grammarCheck:
            return String(localized: "Grammar Check", comment: "Output type name")
        case .translate:
            return String(localized: "Translate", comment: "Output type name")
        }
    }
}

// MARK: - Built-in Structured Output Templates

public extension ActionConfig.StructuredOutputConfig {
    /// JSON field name used for the sentence-pairs primary field. The same
    /// identifier appears in the `jsonSchema` payload below; keep them in sync.
    static let sentencePairsFieldName = "sentence_pairs"

    /// Template for sentence-by-sentence translation
    static let sentencePairs = ActionConfig.StructuredOutputConfig(
        primaryField: sentencePairsFieldName,
        additionalFields: [],
        jsonSchema: """
        {
          "name": "sentence_translate_response",
          "schema": {
            "type": "object",
            "properties": {
              "sentence_pairs": {
                "type": "array",
                "description": "Array of sentence pairs with original and translated text.",
                "items": {
                  "type": "object",
                  "properties": {
                    "original": {
                      "type": "string",
                      "description": "The original sentence from the input."
                    },
                    "translation": {
                      "type": "string",
                      "description": "The translated version of the sentence."
                    }
                  },
                  "required": ["original", "translation"],
                  "additionalProperties": false
                }
              }
            },
            "required": ["sentence_pairs"],
            "additionalProperties": false
          }
        }
        """
    )

    /// Template for grammar check with revised text and explanations
    static let grammarCheck = ActionConfig.StructuredOutputConfig(
        primaryField: "revised_text",
        additionalFields: ["additional_text"],
        jsonSchema: """
        {
          "name": "grammar_check_response",
          "schema": {
            "type": "object",
            "properties": {
              "revised_text": {
                "type": "string",
                "description": "The user text rewritten with all grammar issues addressed. Preserve the original language."
              },
              "additional_text": {
                "type": "string",
                "description": "Any requested explanations, analyses, or translations that accompany the revised text."
              }
            },
            "required": [
              "revised_text",
              "additional_text"
            ],
            "additionalProperties": false
          }
        }
        """
    )
}
