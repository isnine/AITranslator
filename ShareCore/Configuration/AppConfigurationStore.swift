//
//  AppConfigurationStore.swift
//  ShareCore
//
//  Created by Codex on 2025/10/19.
//

import Foundation
import Combine

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
            return "gpt-5-mini"
        case .custom:
            return "--"
        }
    }
}

public struct ActionConfig: Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var prompt: String
    public var providerIDs: [UUID]

    public init(id: UUID = UUID(), name: String, prompt: String, providerIDs: [UUID]) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.providerIDs = providerIDs
    }
}

public struct ProviderConfig: Identifiable, Hashable {
    public let id: UUID
    public var displayName: String
    public var apiURL: URL
    public var token: String
    public var authHeaderName: String
    public var category: ProviderCategory
    public var modelName: String

    public init(
        id: UUID = UUID(),
        displayName: String,
        apiURL: URL,
        token: String,
        authHeaderName: String = "api-key",
        category: ProviderCategory = .custom,
        modelName: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.apiURL = apiURL
        self.token = token
        self.authHeaderName = authHeaderName
        self.category = category
        self.modelName = modelName ?? category.defaultModelHint
    }
}

@MainActor
public final class AppConfigurationStore: ObservableObject {
    public static let shared = AppConfigurationStore()

    @Published public private(set) var actions: [ActionConfig]
    @Published public private(set) var providers: [ProviderConfig]

    public var defaultAction: ActionConfig? {
        actions.first
    }

    public var defaultProvider: ProviderConfig? {
        providers.first
    }

    private init() {
        let defaultProvider = ProviderConfig(
            displayName: "Azure OpenAI",
            apiURL: URL(string: "https://REDACTED_AZURE_ENDPOINT/openai/deployments/gpt-5-mini/chat/completions?api-version=2025-01-01-preview")!,
            token: "REDACTED_AZURE_API_KEY",
            category: .azureOpenAI,
            modelName: "gpt-5-mini"
        )

        let defaultAction = ActionConfig(
            name: "智能翻译",
            prompt: "请对用户选中的文本进行智能翻译，保留原意并输出简洁结果。",
            providerIDs: [defaultProvider.id]
        )

        self.actions = [defaultAction]
        self.providers = [defaultProvider]
    }

    public func updateActions(_ actions: [ActionConfig]) {
        self.actions = actions
    }

    public func updateProviders(_ providers: [ProviderConfig]) {
        self.providers = providers
    }
}
