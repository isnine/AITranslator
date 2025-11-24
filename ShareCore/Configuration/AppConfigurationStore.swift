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
    private let preferences: AppPreferences
    private var cancellables: Set<AnyCancellable> = []

    public var defaultAction: ActionConfig? {
        actions.first
    }

    public var defaultProvider: ProviderConfig? {
        providers.first
    }

    private init(preferences: AppPreferences = .shared) {
        self.preferences = preferences

        preferences.refreshFromDefaults()

        let providers = [Defaults.provider, Defaults.gpt5NanoProvider]
        self.providers = providers
        let baseActions = Defaults.actions(for: providers.map { $0.id })
        self.actions = AppConfigurationStore.applyTargetLanguage(
            baseActions,
            targetLanguage: preferences.targetLanguage
        )

        preferences.$targetLanguage
            .receive(on: RunLoop.main)
            .sink { [weak self] option in
                guard let self else { return }
                let updated = AppConfigurationStore.applyTargetLanguage(
                    self.actions,
                    targetLanguage: option
                )
                self.actions = updated
            }
            .store(in: &cancellables)
    }

    public func updateActions(_ actions: [ActionConfig]) {
        let adjusted = AppConfigurationStore.applyTargetLanguage(
            actions,
            targetLanguage: preferences.targetLanguage
        )
        self.actions = adjusted
    }

    public func updateProviders(_ providers: [ProviderConfig]) {
        self.providers = providers
    }

    private static func applyTargetLanguage(
        _ actions: [ActionConfig],
        targetLanguage: TargetLanguageOption
    ) -> [ActionConfig] {
        actions.map { action in
            guard let template = ManagedActionTemplate(action: action) else {
                return action
            }

            var updated = action

            if template.shouldUpdatePrompt(currentPrompt: action.prompt) {
                updated.prompt = template.prompt(for: targetLanguage)
            }

            if let summaryText = template.summary(for: targetLanguage),
               template.shouldUpdateSummary(currentSummary: action.summary) {
                updated.summary = summaryText
            }

            return updated
        }
    }
}

private extension AppConfigurationStore {
    enum Defaults {
        static let translateName = NSLocalizedString(
            "Translate",
            comment: "Name of the translate action"
        )
        static let summarizeName = NSLocalizedString(
            "Summarize",
            comment: "Name of the summarize action"
        )
        static let polishName = NSLocalizedString(
            "Polish",
            comment: "Name of the polish action"
        )
        static let grammarCheckName = NSLocalizedString(
            "Grammar Check",
            comment: "Name of the grammar check action"
        )
        static let sentenceAnalysisName = NSLocalizedString(
            "Sentence Analysis",
            comment: "Name of the sentence analysis action"
        )
        static let translateLegacySummary = "Use AI for context-aware translation."
        static let translateLegacyPrompt = "Translate the selected text intelligently, keep the original meaning, and return a concise result."
        static let summarizeLegacyPrompt = "Provide a concise summary of the selected text, preserving the key meaning."
        static let sentenceAnalysisSummary = "Parse sentence grammar and highlight reusable phrases."

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
                    name: translateName,
                    summary: translateLegacySummary,
                    prompt: translateLegacyPrompt,
                    providerIDs: providerIDs,
                    usageScenes: .all
                ),
                .init(
                    name: summarizeName,
                    summary: "Generate a concise summary of the text.",
                    prompt: summarizeLegacyPrompt,
                    providerIDs: providerIDs,
                    usageScenes: .all
                ),
                .init(
                    name: polishName,
                    summary: "Rewrite the text in the same language with improved clarity.",
                    prompt: "Polish the text and return the improved version in the same language.",
                    providerIDs: providerIDs,
                    usageScenes: .all,
                    showsDiff: true
                ),
                .init(
                    name: grammarCheckName,
                    summary: "Inspect grammar issues and provide explanations.",
                    prompt: "Review this text for grammar issues. 1. Return a polished version first. 2. On the next line, explain each original error in Chinese, prefixing severe ones with ❌ and minor ones with ⚠️. 3. End with the polished sentence's meaning translated into Chinese.",
                    providerIDs: providerIDs,
                    usageScenes: .all,
                    showsDiff: true,
                    structuredOutput: .init(
                        primaryField: "revised_text",
                        additionalFields: ["additional_text"],
                        jsonSchema: """
                        {
                          "name": "grammar_check_response",
                          "schema": {
                            "type": "object",
                            "properties": {
                              "revised_text": {
                                "type": "string",
                                "description": "The user text rewritten with all grammar issues addressed. Preserve the original language."
                              },
                              "additional_text": {
                                "type": "string",
                                "description": "Any requested explanations, analyses, or translations that accompany the revised text."
                              }
                            },
                            "required": [
                              "revised_text",
                              "additional_text"
                            ],
                            "additionalProperties": false
                          }
                        }
                        """
                    )
                ),
                .init(
                    name: sentenceAnalysisName,
                    summary: sentenceAnalysisSummary,
                    prompt: ManagedActionTemplate.sentenceAnalysisPrompt(for: .appLanguage),
                    providerIDs: providerIDs,
                    usageScenes: .all
                )
            ]
        }
    }

    enum ManagedActionTemplate {
        case translate
        case summarize
        case sentenceAnalysis

        init?(action: ActionConfig) {
            switch action.name {
            case Defaults.translateName:
                self = .translate
            case Defaults.summarizeName:
                self = .summarize
            case Defaults.sentenceAnalysisName:
                self = .sentenceAnalysis
            default:
                return nil
            }
        }

        func prompt(for language: TargetLanguageOption) -> String {
            switch self {
            case .translate:
                return Self.translatePrompt(for: language)
            case .summarize:
                return "Provide a concise summary of the selected text in \(language.promptDescriptor). Preserve the essential meaning without adding new information."
            case .sentenceAnalysis:
                return Self.sentenceAnalysisPrompt(for: language)
            }
        }

        func summary(for language: TargetLanguageOption) -> String? {
            switch self {
            case .translate:
                return "Translate into \(language.promptDescriptor) while keeping the original tone."
            case .summarize:
                return nil
            case .sentenceAnalysis:
                return nil
            }
        }

        func shouldUpdatePrompt(currentPrompt: String) -> Bool {
            let generated = Set(
                TargetLanguageOption.selectionOptions.map { prompt(for: $0) }
            )

            switch self {
            case .translate:
                var acceptable = generated
                acceptable.formUnion(
                    TargetLanguageOption.selectionOptions.map { Self.translateLegacyPrompt(for: $0) }
                )
                acceptable.insert(Defaults.translateLegacyPrompt)
                return acceptable.contains(currentPrompt)
            case .summarize:
                return currentPrompt == Defaults.summarizeLegacyPrompt || generated.contains(currentPrompt)
            case .sentenceAnalysis:
                return generated.contains(currentPrompt)
            }
        }

        func shouldUpdateSummary(currentSummary: String) -> Bool {
            switch self {
            case .translate:
                let generated = Set(
                    TargetLanguageOption.selectionOptions.compactMap {
                        summary(for: $0)
                    }
                )
                return currentSummary == Defaults.translateLegacySummary || generated.contains(currentSummary)
            case .summarize:
                return false
            case .sentenceAnalysis:
                return false
            }
        }

        private static func translatePrompt(for language: TargetLanguageOption) -> String {
            let descriptor = language.promptDescriptor
            return "Translate the selected text into \(descriptor). If the input language already matches the target language, translate it into English instead. Preserve tone, intent, and terminology. Respond with only the translated text."
        }

        private static func translateLegacyPrompt(for language: TargetLanguageOption) -> String {
            "Translate the selected text into \(language.promptDescriptor). Preserve tone, intent, and terminology. Respond with only the translated text."
        }

        static func sentenceAnalysisPrompt(for language: TargetLanguageOption) -> String {
            let descriptor = language.promptDescriptor
            return """
            Analyze the provided sentence or short paragraph and respond entirely in \(descriptor). Follow exactly two Markdown sections:

            ## 📚语法分析
            - Explain the sentence structure (clauses, parts of speech, tense/voice) and how key components relate.
            - Highlight noteworthy grammar patterns or difficult constructions.

            ## ✍️ 搭配积累
            - List useful short phrases, collocations, or idiomatic chunks from the input.
            - Give each item a brief meaning plus usage tips or a short example.

            Keep explanations concise yet insightful and do not add extra sections.
            """
        }
    }
}
