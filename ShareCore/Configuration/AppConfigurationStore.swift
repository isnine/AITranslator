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
            return "model-router"
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
            apiURL: URL(string: "https://REDACTED_AZURE_ENDPOINT/openai/deployments/model-router/chat/completions?api-version=2025-01-01-preview")!,
            token: "REDACTED_AZURE_API_KEY",
            category: .azureOpenAI,
            modelName: "model-router"
        )

        let defaultAction = ActionConfig(
            name: "翻译",
            prompt: "请对用户选中的文本进行智能翻译，保留原意并输出简洁结果。",
            providerIDs: [defaultProvider.id]
        )

      let summaryAction = ActionConfig(
          name: "总结",
          prompt: "尽量简短的对用户选中的文本进行文本总结，保留原意并输出简洁结果。",
          providerIDs: [defaultProvider.id]
      )

      let polishAction = ActionConfig(
          name: "打磨",
          prompt: "对文本进行打磨，然后以相同的语言输出打磨后的文本",
          providerIDs: [defaultProvider.id]
      )

      let grammarCheck = ActionConfig(
          name: "语法检查",
          prompt: "请帮我检查这段文本的语法错误。1.首先返回一段打磨的句子版本 2.然后换行再以中文逐一解释原始句子的语法错误有哪些，为什么这么修改。对于严重的错误以❌开头，对于轻微的使用⚠️开头。 3.最后换行显示打磨后文本的中文翻译意思.",
          providerIDs: [defaultProvider.id]
      )

        self.actions = [defaultAction, summaryAction, polishAction, grammarCheck]
        self.providers = [defaultProvider]
    }

    public func updateActions(_ actions: [ActionConfig]) {
        self.actions = actions
    }

    public func updateProviders(_ providers: [ProviderConfig]) {
        self.providers = providers
    }
}
