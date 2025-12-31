//
//  ActionConfig.swift
//  ShareCore
//
//  Created by Codex on 2025/10/19.
//

import Foundation

/// Represents a specific deployment of a provider that can be used for actions.
public struct ProviderDeployment: Hashable, Codable, Identifiable, Sendable {
    public var id: String { "\(providerID.uuidString):\(deployment)" }
    public let providerID: UUID
    public let deployment: String

    public init(providerID: UUID, deployment: String) {
        self.providerID = providerID
        self.deployment = deployment
    }
}

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

public struct ActionConfig: Identifiable, Hashable, Codable {
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

    public struct UsageScene: OptionSet, Hashable, Codable {
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
    /// Selected provider deployments (providerID + deployment name)
    public var providerDeployments: [ProviderDeployment]
    public var usageScenes: UsageScene
    public var outputType: OutputType

    /// Legacy computed property for backward compatibility - returns unique provider IDs
    public var providerIDs: [UUID] {
        Array(Set(providerDeployments.map(\.providerID)))
    }

    /// Computed property for backward compatibility
    public var showsDiff: Bool {
        outputType.showsDiff
    }

    /// Computed property for backward compatibility
    public var structuredOutput: StructuredOutputConfig? {
        outputType.structuredOutput
    }

    /// Computed property for backward compatibility
    public var displayMode: DisplayMode {
        outputType.displayMode
    }

    /// Primary initializer using ProviderDeployments
    public init(
        id: UUID = UUID(),
        name: String,
        summary: String,
        prompt: String,
        providerDeployments: [ProviderDeployment],
        usageScenes: UsageScene = .all,
        outputType: OutputType = .plain
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.prompt = prompt
        self.providerDeployments = providerDeployments
        self.usageScenes = usageScenes
        self.outputType = outputType
    }

    /// Legacy initializer using providerIDs (for backward compatibility)
    /// Creates a deployment for the first deployment of each provider
    public init(
        id: UUID = UUID(),
        name: String,
        summary: String,
        prompt: String,
        providerIDs: [UUID],
        usageScenes: UsageScene = .all,
        outputType: OutputType = .plain
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.prompt = prompt
        // For backward compatibility, create deployments without specific deployment names
        // These will be resolved to the first deployment when used
        self.providerDeployments = providerIDs.map { ProviderDeployment(providerID: $0, deployment: "") }
        self.usageScenes = usageScenes
        self.outputType = outputType
    }

    /// Legacy initializer for backward compatibility
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
        self.providerDeployments = providerIDs.map { ProviderDeployment(providerID: $0, deployment: "") }
        self.usageScenes = usageScenes

        // Infer outputType from legacy parameters
        if displayMode == .sentencePairs {
            self.outputType = .sentencePairs
        } else if structuredOutput?.primaryField == "revised_text" {
            self.outputType = .grammarCheck
        } else if showsDiff {
            self.outputType = .diff
        } else {
            self.outputType = .plain
        }
    }
}
