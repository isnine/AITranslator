//
//  ProviderCategory.swift
//  ShareCore
//
//  Created by Codex on 2025/10/19.
//

import Foundation

public enum ProviderCategory: String, Codable, CaseIterable {
    case openAI = "OpenAI"
    case azureOpenAI = "Azure OpenAI"
    case custom = "Custom"

    public var displayName: String { rawValue }

    public var defaultModelHint: String {
        switch self {
        case .openAI:
            return "gpt-4o"
        case .azureOpenAI:
            return "model-router"
        case .custom:
            return "--"
        }
    }
}
