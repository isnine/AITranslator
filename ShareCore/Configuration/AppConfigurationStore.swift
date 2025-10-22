//
//  AppConfigurationStore.swift
//  ShareCore
//
//  Created by Codex on 2025/10/19.
//

import Foundation
import Combine

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
      self.providers = [Defaults.provider, Defaults.gpt5Provider]
      self.actions = Defaults.actions(for: [Defaults.provider.id, Defaults.gpt5Provider.id])
    }

    public func updateActions(_ actions: [ActionConfig]) {
        self.actions = actions
    }

    public func updateProviders(_ providers: [ProviderConfig]) {
        self.providers = providers
    }
}

private enum Defaults {


    static let provider: ProviderConfig = .init(
        displayName: "Azure OpenAI",
        apiURL: URL(
          string: "https://REDACTED_AZURE_ENDPOINT/openai/deployments/model-router/chat/completions?api-version=2025-01-01-preview"
      )!,
        token: "REDACTED_AZURE_API_KEY",
        authHeaderName: "api-key",
        category: .azureOpenAI,
        modelName: "model-router"
    )

  static let gpt5Provider: ProviderConfig = .init(
      displayName: "Azure OpenAI",
      apiURL: URL(
        string: "https://REDACTED_AZURE_ENDPOINT/openai/deployments/gpt-5/chat/completions?api-version=2025-01-01-preview"
    )!,
      token: "REDACTED_AZURE_API_KEY",
      authHeaderName: "api-key",
      category: .azureOpenAI,
      modelName: "gpt-5"
  )

    static func actions(for providerIDs: [UUID]) -> [ActionConfig] {
        [
            .init(
                name: "翻译",
                prompt: "请对用户选中的文本进行智能翻译，保留原意并输出简洁结果。",
                providerIDs: providerIDs,
                usageScenes: [.app, .contextRead]
            ),
            .init(
                name: "总结",
                prompt: "尽量简短的对用户选中的文本进行文本总结，保留原意并输出简洁结果。",
                providerIDs: providerIDs,
                usageScenes: [.app, .contextRead]
            ),
            .init(
                name: "打磨",
                prompt: "对文本进行打磨，然后以相同的语言输出打磨后的文本",
                providerIDs: providerIDs,
                usageScenes: [.app, .contextEdit]
            ),
            .init(
                name: "语法检查",
                prompt: "请帮我检查这段文本的语法错误。1.首先返回一段打磨的句子版本 2.然后换行再以中文逐一解释原始句子的语法错误有哪些，为什么这么修改。对于严重的错误以❌开头，对于轻微的使用⚠️开头。 3.最后换行显示打磨后文本的中文翻译意思.",
                providerIDs: providerIDs,
                usageScenes: [.app, .contextEdit]
            )
        ]
    }
}
