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
    @Published public private(set) var currentConfigurationName: String?

    private let preferences: AppPreferences
    private let configFileManager: ConfigurationFileManager
    private var cancellables: Set<AnyCancellable> = []

    public var defaultAction: ActionConfig? {
        actions.first
    }

    public var defaultProvider: ProviderConfig? {
        providers.first
    }

    private init(
        preferences: AppPreferences = .shared,
        configFileManager: ConfigurationFileManager = .shared
    ) {
        self.preferences = preferences
        self.configFileManager = configFileManager
        preferences.refreshFromDefaults()

        // Initialize with empty arrays first
        self.providers = []
        self.actions = []
        self.currentConfigurationName = nil

        // Then load from persistence or defaults
        loadConfiguration()

        // Use dropFirst() to skip the initial value emission,
        // so we only save on actual user-initiated changes
        preferences.$targetLanguage
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] option in
                guard let self else { return }
                let updated = AppConfigurationStore.applyTargetLanguage(
                    self.actions,
                    targetLanguage: option
                )
                self.actions = updated
                self.saveConfiguration()
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    public func updateActions(_ actions: [ActionConfig]) {
        let adjusted = AppConfigurationStore.applyTargetLanguage(
            actions,
            targetLanguage: preferences.targetLanguage
        )
        self.actions = adjusted
        saveConfiguration()
    }

    public func updateProviders(_ providers: [ProviderConfig]) {
        self.providers = providers
        saveConfiguration()
    }

    public func setCurrentConfigurationName(_ name: String?) {
        self.currentConfigurationName = name
        preferences.setCurrentConfigName(name)
    }

    // MARK: - Persistence using ConfigurationFileManager

    private func loadConfiguration() {
        // Step 1: Read current config name from UserDefaults
        let storedName = preferences.currentConfigName
        print("[ConfigStore] Stored config name from UserDefaults: \(storedName ?? "nil")")

        // Step 2: Try to load the named configuration
        if let name = storedName {
            if tryLoadConfiguration(named: name) {
                print("[ConfigStore] ✅ Successfully loaded config: '\(name)'")
                return
            }
            print("[ConfigStore] ⚠️ Failed to load stored config '\(name)', trying fallback...")
        }

        // Step 3: Fallback - try to load any available configuration
        let availableConfigs = configFileManager.listConfigurations()
        print("[ConfigStore] Available configs: \(availableConfigs.map { $0.name })")

        for configInfo in availableConfigs {
            if tryLoadConfiguration(named: configInfo.name) {
                print("[ConfigStore] ✅ Loaded fallback config: '\(configInfo.name)'")
                preferences.setCurrentConfigName(configInfo.name)
                return
            }
        }

        // Step 4: No configuration available - create empty configuration
        print("[ConfigStore] ⚠️ No configurations available, creating empty configuration...")
        createEmptyConfiguration()
    }

    private func tryLoadConfiguration(named name: String) -> Bool {
        do {
            let config = try configFileManager.loadConfiguration(named: name)
            applyLoadedConfiguration(config)
            self.currentConfigurationName = name
            preferences.setCurrentConfigName(name)

            // Apply preferences if present
            if let prefsConfig = config.preferences {
                if let targetLang = prefsConfig.targetLanguage,
                   let option = TargetLanguageOption(rawValue: targetLang) {
                    preferences.setTargetLanguage(option)
                }
            }

            // Apply TTS if present
            if let ttsEntry = config.tts {
                let usesDefault = ttsEntry.useDefault ?? true
                preferences.setTTSUsesDefaultConfiguration(usesDefault)
                let ttsConfig = ttsEntry.toTTSConfiguration()
                preferences.setTTSConfiguration(ttsConfig)
            }

            return true
        } catch {
            print("[ConfigStore] Failed to load config '\(name)': \(error)")
            return false
        }
    }

    private func createEmptyConfiguration() {
        self.providers = []
        self.actions = []
        self.currentConfigurationName = "New Configuration"
        preferences.setCurrentConfigName("New Configuration")

        // Save the empty configuration
        saveConfiguration()
    }
    
    private func applyLoadedConfiguration(_ config: AppConfiguration) {
        // Build provider map
        var loadedProviders: [ProviderConfig] = []
        var providerNameToID: [String: UUID] = [:]
        
        print("[ConfigStore] Parsing \(config.providers.count) providers from config")
        
        for (name, entry) in config.providers {
            print("[ConfigStore] Trying to parse provider: '\(name)' with category: '\(entry.category)'")
            if let provider = entry.toProviderConfig(name: name) {
                loadedProviders.append(provider)
                providerNameToID[name] = provider.id
                print("[ConfigStore] ✅ Successfully parsed provider: '\(name)'")
            } else {
                print("[ConfigStore] ❌ Failed to parse provider: '\(name)' - toProviderConfig returned nil")
            }
        }
        
        print("[ConfigStore] Total loaded providers: \(loadedProviders.count)")
        
        // Build actions (actions is now an array, order is preserved)
        var loadedActions: [ActionConfig] = []
        for entry in config.actions {
            let action = entry.toActionConfig(providerMap: providerNameToID)
            loadedActions.append(action)
        }
        
        print("[ConfigStore] Total loaded actions: \(loadedActions.count)")
        
        self.providers = loadedProviders
        self.actions = AppConfigurationStore.applyTargetLanguage(
            loadedActions,
            targetLanguage: preferences.targetLanguage
        )
    }
    
    private func saveConfiguration() {
        guard let configName = currentConfigurationName else {
            print("[ConfigStore] No current configuration name set, skipping save")
            return
        }

        let config = buildCurrentConfiguration()

        do {
            try configFileManager.saveConfiguration(config, name: configName)
            print("[ConfigStore] ✅ Saved configuration to '\(configName).json'")
        } catch {
            print("[ConfigStore] ❌ Failed to save configuration: \(error)")
        }
    }
    
    private func buildCurrentConfiguration() -> AppConfiguration {
        // Build provider entries
        var providerEntries: [String: AppConfiguration.ProviderEntry] = [:]
        var providerIDToName: [UUID: String] = [:]
        
        for provider in providers {
            let (name, entry) = AppConfiguration.ProviderEntry.from(provider)
            var uniqueName = name
            var counter = 1
            while providerEntries[uniqueName] != nil {
                counter += 1
                uniqueName = "\(name) \(counter)"
            }
            providerEntries[uniqueName] = entry
            providerIDToName[provider.id] = uniqueName
        }
        
        // Build action entries (as array to preserve order)
        let actionEntries = actions.map { action in
            AppConfiguration.ActionEntry.from(
                action,
                providerNames: providerIDToName
            )
        }
        
        return AppConfiguration(
            version: "1.0.0",
            preferences: AppConfiguration.PreferencesConfig(
                targetLanguage: preferences.targetLanguage.rawValue
            ),
            providers: providerEntries,
            tts: AppConfiguration.TTSEntry.from(
                preferences.effectiveTTSConfiguration,
                usesDefault: preferences.ttsUsesDefaultConfiguration
            ),
            actions: actionEntries
        )
    }

    /// Reset to bundled default configuration
    public func resetToDefault() {
        // Try to load the "Default" configuration from ConfigurationFileManager
        if tryLoadConfiguration(named: "Default") {
            print("[ConfigStore] ✅ Reset to Default configuration")
            return
        }

        // If Default doesn't exist, create empty configuration
        print("[ConfigStore] Default configuration not found, creating empty configuration")
        createEmptyConfiguration()
    }

    /// Switch to a different configuration by name
    public func switchConfiguration(to name: String) -> Bool {
        if tryLoadConfiguration(named: name) {
            print("[ConfigStore] ✅ Switched to configuration: '\(name)'")
            return true
        }
        print("[ConfigStore] ❌ Failed to switch to configuration: '\(name)'")
        return false
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

// MARK: - Managed Action Templates (for language updates)

private extension AppConfigurationStore {
    enum ManagedActionTemplate {
        case translate
        case summarize
        case sentenceAnalysis
        case sentenceBySentenceTranslate

        private static let translateName = NSLocalizedString(
            "Translate",
            comment: "Name of the translate action"
        )
        private static let summarizeName = NSLocalizedString(
            "Summarize",
            comment: "Name of the summarize action"
        )
        private static let sentenceAnalysisName = NSLocalizedString(
            "Sentence Analysis",
            comment: "Name of the sentence analysis action"
        )
        private static let sentenceBySentenceTranslateName = NSLocalizedString(
            "Sentence Translate",
            comment: "Name of the sentence-by-sentence translation action"
        )
        
        private static let translateLegacySummary = "Use AI for context-aware translation."
        private static let translateLegacyPrompt = "Translate the selected text intelligently, keep the original meaning, and return a concise result."
        private static let summarizeLegacyPrompt = "Provide a concise summary of the selected text, preserving the key meaning."

        init?(action: ActionConfig) {
            switch action.name {
            case Self.translateName:
                self = .translate
            case Self.summarizeName:
                self = .summarize
            case Self.sentenceAnalysisName:
                self = .sentenceAnalysis
            case Self.sentenceBySentenceTranslateName:
                self = .sentenceBySentenceTranslate
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
            case .sentenceBySentenceTranslate:
                return Self.sentenceBySentenceTranslatePrompt(for: language)
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
            case .sentenceBySentenceTranslate:
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
                acceptable.insert(Self.translateLegacyPrompt)
                return acceptable.contains(currentPrompt)
            case .summarize:
                return currentPrompt == Self.summarizeLegacyPrompt || generated.contains(currentPrompt)
            case .sentenceAnalysis:
                return generated.contains(currentPrompt)
            case .sentenceBySentenceTranslate:
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
                return currentSummary == Self.translateLegacySummary || generated.contains(currentSummary)
            case .summarize:
                return false
            case .sentenceAnalysis:
                return false
            case .sentenceBySentenceTranslate:
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

        static func sentenceBySentenceTranslatePrompt(for language: TargetLanguageOption) -> String {
            let descriptor = language.promptDescriptor
            return """
            Translate the following text sentence by sentence into \(descriptor). If the input language already matches the target language, translate it into English instead. Split the input into individual sentences, keeping punctuation with each sentence. For each sentence, provide the original text and its translation as a pair. Preserve the original meaning, tone, and style.
            """
        }
    }
}
