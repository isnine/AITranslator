//
//  ProviderCategory.swift
//  ShareCore
//
//  Created by Codex on 2025/10/19.
//

import Foundation

public enum ProviderCategory: String, Codable, CaseIterable {
    case azureOpenAI = "Azure OpenAI"
    case builtInCloud = "Built-in Cloud"
    case custom = "Custom"

    public var displayName: String { rawValue }

    public var defaultModelHint: String {
        switch self {
        case .azureOpenAI:
            return "model-router"
        case .builtInCloud:
            return "model-router"
        case .custom:
            return "--"
        }
    }

    /// Whether this category uses the built-in CloudFlare proxy
    public var usesBuiltInProxy: Bool {
        self == .builtInCloud
    }

    /// Categories available for user selection in the UI
    public static var editableCategories: [ProviderCategory] {
        [.builtInCloud, .azureOpenAI, .custom]
    }

    /// Description for each category
    public var categoryDescription: String {
        switch self {
        case .builtInCloud:
            return "Use built-in cloud service, no configuration needed"
        case .azureOpenAI:
            return "Connect to your Azure OpenAI deployment"
        case .custom:
            return "Connect to a custom OpenAI-compatible API"
        }
    }

    /// Whether this category requires endpoint configuration
    public var requiresEndpointConfig: Bool {
        self != .builtInCloud
    }
}
