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
      let providers = [Defaults.provider, Defaults.gpt5NanoProvider]
      self.providers = providers
      self.actions = Defaults.actions(for: providers.map { $0.id })
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

  static let gpt5NanoProvider: ProviderConfig = .init(
      displayName: "Azure OpenAI",
      apiURL: URL(
        string: "https://REDACTED_AZURE_ENDPOINT/openai/deployments/gpt-5-nano/chat/completions?api-version=2025-01-01-preview"
    )!,
      token: "REDACTED_AZURE_API_KEY",
      authHeaderName: "api-key",
      category: .azureOpenAI,
      modelName: "gpt-5-nano"
  )

    static func actions(for providerIDs: [UUID]) -> [ActionConfig] {
        [
            .init(
                name: "Translate",
                summary: "Use AI for context-aware translation.",
                prompt: "Translate the selected text intelligently, keep the original meaning, and return a concise result.",
                providerIDs: providerIDs,
                usageScenes: [.app, .contextRead]
            ),
            .init(
                name: "Summarize",
                summary: "Generate a concise summary of the text.",
                prompt: "Provide a concise summary of the selected text, preserving the key meaning.",
                providerIDs: providerIDs,
                usageScenes: [.app, .contextRead]
            ),
            .init(
                name: "Polish",
                summary: "Rewrite the text in the same language with improved clarity.",
                prompt: "Polish the text and return the improved version in the same language.",
                providerIDs: providerIDs,
                usageScenes: [.app, .contextEdit],
                showsDiff: true
            ),
            .init(
                name: "Grammar Check",
                summary: "Inspect grammar issues and provide explanations.",
                prompt: "Review this text for grammar issues. 1. Return a polished version first. 2. On the next line, explain each original error in Chinese, prefixing severe ones with ❌ and minor ones with ⚠️. 3. End with the polished sentence's meaning translated into Chinese.",
                providerIDs: providerIDs,
                usageScenes: [.app, .contextEdit]
            )
        ]
    }
}
