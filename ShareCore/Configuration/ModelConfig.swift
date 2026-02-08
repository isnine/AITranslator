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

    private enum CodingKeys: String, CodingKey {
        case id, displayName, isDefault, isPremium, supportsVision
    }

    public init(id: String, displayName: String, isDefault: Bool = false, isPremium: Bool = false, supportsVision: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.isDefault = isDefault
        self.isPremium = isPremium
        self.supportsVision = supportsVision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
        isPremium = try container.decode(Bool.self, forKey: .isPremium)
        supportsVision = try container.decodeIfPresent(Bool.self, forKey: .supportsVision) ?? true
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
    /// CloudFlare worker endpoint for the built-in cloud service
    public static var endpoint: URL {
        BuildEnvironment.cloudEndpoint
    }

    /// Shared secret for HMAC signing
    public static var secret: String {
        BuildEnvironment.cloudSecret
    }

    /// API version parameter
    public static let apiVersion = BuildEnvironment.apiVersion
}
