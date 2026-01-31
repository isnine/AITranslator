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

    public init(id: String, displayName: String, isDefault: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.isDefault = isDefault
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
