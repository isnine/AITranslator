//
//  ActionConfig.swift
//  ShareCore
//
//  Created by Codex on 2025/10/19.
//

import Foundation

/// Represents a single sentence pair with original and translated text.
public struct SentencePair: Codable, Hashable, Identifiable, Sendable {
    public var id: String { original + translation }
    public let original: String
    public let translation: String

    public init(original: String, translation: String) {
        self.original = original
        self.translation = translation
    }

    enum CodingKeys: String, CodingKey {
        case original, translation
    }
}

public struct ActionConfig: Identifiable, Hashable {
    /// Controls how the result is displayed in the UI.
    public enum DisplayMode: String, Codable, Hashable {
        /// Default text display with copy/speak buttons.
        case standard
        /// Sentence-by-sentence alternating rows (original + translation).
        case sentencePairs
    }

    public struct StructuredOutputConfig: Codable, Hashable {
        public let primaryField: String
        public let additionalFields: [String]
        public let jsonSchema: String

        public init(primaryField: String, additionalFields: [String], jsonSchema: String) {
            self.primaryField = primaryField
            self.additionalFields = additionalFields
            self.jsonSchema = jsonSchema
        }

        public func responseFormatPayload() -> [String: Any]? {
            guard let schemaObject = jsonSchemaObject() else {
                return nil
            }

            return [
                "type": "json_schema",
                "json_schema": schemaObject
            ]
        }

        private func jsonSchemaObject() -> [String: Any]? {
            guard let data = jsonSchema.data(using: .utf8) else {
                return nil
            }
            let object = try? JSONSerialization.jsonObject(with: data, options: [])
            return object as? [String: Any]
        }
    }

    public struct UsageScene: OptionSet, Hashable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let app = UsageScene(rawValue: 1 << 0)
        public static let contextRead = UsageScene(rawValue: 1 << 1)
        public static let contextEdit = UsageScene(rawValue: 1 << 2)

        public static let all: UsageScene = [.app, .contextRead, .contextEdit]
    }

    public let id: UUID
    public var name: String
    public var summary: String
    public var prompt: String
    public var providerIDs: [UUID]
    public var usageScenes: UsageScene
    public var showsDiff: Bool
    public var structuredOutput: StructuredOutputConfig?
    public var displayMode: DisplayMode

    public init(
        id: UUID = UUID(),
        name: String,
        summary: String,
        prompt: String,
        providerIDs: [UUID],
        usageScenes: UsageScene = .all,
        showsDiff: Bool = false,
        structuredOutput: StructuredOutputConfig? = nil,
        displayMode: DisplayMode = .standard
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.prompt = prompt
        self.providerIDs = providerIDs
        self.usageScenes = usageScenes
        self.showsDiff = showsDiff
        self.structuredOutput = structuredOutput
        self.displayMode = displayMode
    }
}
