//
//  ModelConfig.swift
//  ShareCore
//
//  Created by Codex on 2025/01/27.
//

import Foundation

/// Represents a single model available from the cloud API
public struct ModelConfig: Identifiable, Hashable, Codable, Sendable {
    /// Unique model identifier (e.g., "gpt-4.1-nano")
    public let id: String

    /// Human-readable display name (e.g., "GPT-4.1 Nano")
    public let displayName: String

    /// Whether this model is the default selection
    public let isDefault: Bool

    /// Whether this model requires a premium subscription
    public let isPremium: Bool

    /// Whether this model supports vision (image input)
    public let supportsVision: Bool

    /// Optional tags from server (e.g., "latest")
    public let tags: [String]

    /// Whether this model is hidden by default (collapsed in UI)
    public let hidden: Bool

    private enum CodingKeys: String, CodingKey {
        case id, displayName, isDefault, isPremium, supportsVision, tags, hidden
    }

    public init(id: String, displayName: String, isDefault: Bool = false, isPremium: Bool = false, supportsVision: Bool = true, tags: [String] = [], hidden: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.isDefault = isDefault
        self.isPremium = isPremium
        self.supportsVision = supportsVision
        self.tags = tags
        self.hidden = hidden
    }

    /// Well-known identifier for the on-device Apple Translate model.
    public static let appleTranslateID = "apple-translate"

    /// Pre-built ModelConfig for Apple Translate.
    public static let appleTranslate = ModelConfig(
        id: appleTranslateID,
        displayName: "Apple Translate",
        isDefault: false,
        isPremium: false,
        supportsVision: false,
        tags: ["on-device"],
        hidden: false
    )

    /// Whether this model runs locally on-device (e.g. Apple Translate).
    public var isLocal: Bool { id == Self.appleTranslateID }

    /// Whether the given model ID refers to a local/on-device model.
    public static func isLocalModelID(_ id: String) -> Bool {
        id == appleTranslateID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
        isPremium = try container.decode(Bool.self, forKey: .isPremium)
        supportsVision = try container.decodeIfPresent(Bool.self, forKey: .supportsVision) ?? true
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
    }
}

/// Response from /models API endpoint
public struct ModelsResponse: Codable, Sendable {
    public let models: [ModelConfig]

    public init(models: [ModelConfig]) {
        self.models = models
    }
}

// MARK: - Cloud Service Constants

public enum CloudServiceConstants {
    /// Azure Functions endpoint for the built-in cloud service
    public static var endpoint: URL {
        BuildEnvironment.cloudEndpoint
    }

    /// Cloudflare Worker endpoint for marketplace API
    public static let marketplaceEndpoint = URL(string: "https://translator-api.zanderwang.com")!

    /// Shared secret for HMAC signing
    public static var secret: String {
        BuildEnvironment.cloudSecret
    }

    /// API version parameter
    public static let apiVersion = BuildEnvironment.apiVersion
}
