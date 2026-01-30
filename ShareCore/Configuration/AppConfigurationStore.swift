//
//  AppConfigurationStore.swift
//  ShareCore
//
//  Created by Codex on 2025/10/19.
//

import Combine
import Foundation

@MainActor
public final class AppConfigurationStore: ObservableObject {
    public static let shared = AppConfigurationStore()

    @Published public private(set) var actions: [ActionConfig]
    @Published public private(set) var currentConfigurationName: String?

    /// Publisher to notify UI that configuration was switched and UI should sync from preferences
    public let configurationSwitchedPublisher = PassthroughSubject<Void, Never>()

    /// Last validation result from loading or saving
    @Published public private(set) var lastValidationResult: ConfigurationValidationResult?

    /// Whether auto-save is currently suspended (to prevent save loops during file reload)
    private var isSaveSuspended = false

    /// Timestamp of last file modification we initiated
    private var lastSaveTimestamp: Date?

    /// Debounce interval for file change events (to avoid duplicate reloads)
    private static let fileChangeDebounceInterval: TimeInterval = 0.5

    private let preferences: AppPreferences
    private let configFileManager: ConfigurationFileManager
    private var cancellables: Set<AnyCancellable> = []

    public var defaultAction: ActionConfig? {
        actions.first
    }

    private init(
        preferences: AppPreferences = .shared,
        configFileManager: ConfigurationFileManager = .shared
    ) {
        self.preferences = preferences
        self.configFileManager = configFileManager
        preferences.refreshFromDefaults()

        // Initialize with empty arrays first
        actions = []
        currentConfigurationName = nil
        lastValidationResult = nil

        // Then load from persistence or defaults
        loadConfiguration()

        // Subscribe to file change events
        setupFileChangeObserver()

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

    // MARK: - File Change Observer

    private func setupFileChangeObserver() {
        configFileManager.fileChangePublisher
            .debounce(for: .seconds(Self.fileChangeDebounceInterval), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                Task { @MainActor in
                    await self.handleFileChange(event)
                }
            }
            .store(in: &cancellables)
    }

    private func handleFileChange(_ event: ConfigurationFileChangeEvent) async {
        // Only process changes to the current configuration
        guard event.name == currentConfigurationName else { return }

        // Ignore changes we initiated ourselves (within debounce window)
        if let lastSave = lastSaveTimestamp,
           event.timestamp.timeIntervalSince(lastSave) < Self.fileChangeDebounceInterval
        {
            Logger.debug("[ConfigStore] Ignoring file change - self-initiated save")
            return
        }

        switch event.changeType {
        case .modified:
            Logger.debug("[ConfigStore] 🔄 External file modification detected, reloading...")
            reloadCurrentConfiguration()

        case .deleted:
            Logger.debug("[ConfigStore] ⚠️ Configuration file deleted externally")
            // Try to reload from bundled default
            _ = tryLoadConfiguration(named: "Configuration")

        case .renamed:
            Logger.debug("[ConfigStore] ⚠️ Configuration file renamed externally")
            // Try to find the file under a new name or reload
            reloadCurrentConfiguration()
        }
    }

    // MARK: - Public Methods

    /// Update actions with validation
    /// Returns validation result (nil if validation passed or was skipped)
    @discardableResult
    public func updateActions(_ actions: [ActionConfig]) -> ConfigurationValidationResult? {
        return applyActionsUpdate(actions)
    }

    /// Internal method to actually apply actions update
    private func applyActionsUpdate(_ actions: [ActionConfig]) -> ConfigurationValidationResult? {
        let adjusted = AppConfigurationStore.applyTargetLanguage(
            actions,
            targetLanguage: preferences.targetLanguage
        )

        // Validate before applying
        let validationResult = ConfigurationValidator.shared.validateInMemory(
            actions: adjusted
        )

        lastValidationResult = validationResult

        // Apply changes even with warnings, but log them
        if validationResult.hasWarnings {
            for warning in validationResult.warnings {
                Logger.debug("[ConfigStore] ⚠️ Validation warning: \(warning.message)")
            }
        }

        self.actions = adjusted
        saveConfiguration()

        return validationResult.issues.isEmpty ? nil : validationResult
    }

    public func setCurrentConfigurationName(_ name: String?) {
        let previousName = currentConfigurationName
        guard previousName != name else { return }

        // Update file monitoring for the old config
        if let previousName {
            configFileManager.stopMonitoring(configurationNamed: previousName)
        }

        currentConfigurationName = name
        preferences.setCurrentConfigName(name)

        // Start monitoring the new config
        if let newName = name {
            configFileManager.startMonitoring(configurationNamed: newName)
        }
    }

    /// Apply actions directly without triggering the default-mode check
    /// Used by ConfigurationService when loading a configuration
    public func applyActionsDirectly(_ actions: [ActionConfig]) {
        let adjusted = AppConfigurationStore.applyTargetLanguage(
            actions,
            targetLanguage: preferences.targetLanguage
        )
        self.actions = adjusted
        // Don't save - this is part of a load operation
    }

    /// Reload the current configuration from disk
    public func reloadCurrentConfiguration() {
        guard let name = currentConfigurationName else { return }

        // Suspend auto-save during reload to prevent loops
        isSaveSuspended = true
        defer { isSaveSuspended = false }

        if tryLoadConfiguration(named: name) {
            Logger.debug("[ConfigStore] ✅ Reloaded configuration: '\(name)'")
        } else {
            Logger.debug("[ConfigStore] ❌ Failed to reload configuration: '\(name)'")
        }
    }

    /// Validate current in-memory configuration
    public func validateCurrentConfiguration() -> ConfigurationValidationResult {
        let result = ConfigurationValidator.shared.validateInMemory(
            actions: actions
        )
        lastValidationResult = result
        return result
    }

    /// Force save current configuration (bypassing validation errors)
    public func forceSaveConfiguration() {
        saveConfiguration(force: true)
    }

    // MARK: - Persistence using ConfigurationFileManager

    private func loadConfiguration() {
        // Copy bundled default to App Group if needed
        _ = configFileManager.copyBundledDefaultIfNeeded(to: "Configuration")

        // Load from App Group
        if tryLoadConfiguration(named: "Configuration") {
            Logger.debug("[ConfigStore] ✅ Loaded configuration from App Group")
        } else {
            Logger.debug("[ConfigStore] ❌ Failed to load configuration, creating empty")
            createEmptyConfiguration()
        }
    }

    /// Minimum supported configuration version
    private static let minimumVersion = "1.1.0"

    /// Check if a configuration version is compatible (>= 1.1.0)
    private func isVersionCompatible(_ version: String) -> Bool {
        let components = version.split(separator: ".").compactMap { Int($0) }
        let minComponents = Self.minimumVersion.split(separator: ".").compactMap { Int($0) }

        guard components.count >= 2 && minComponents.count >= 2 else {
            return false
        }

        // Compare major version
        if components[0] > minComponents[0] { return true }
        if components[0] < minComponents[0] { return false }

        // Compare minor version
        if components[1] >= minComponents[1] { return true }
        return false
    }

    private func tryLoadConfiguration(named name: String) -> Bool {
        do {
            let config = try configFileManager.loadConfiguration(named: name)

            // Check version compatibility - require 1.1.0 or higher
            if !isVersionCompatible(config.version) {
                Logger.debug("[ConfigStore] ⚠️ Configuration '\(name)' has incompatible version: \(config.version)")
                return false
            }

            // Validate the loaded configuration
            let validationResult = ConfigurationValidator.shared.validate(config)
            lastValidationResult = validationResult

            if validationResult.hasErrors {
                Logger.debug("[ConfigStore] ❌ Configuration '\(name)' has validation errors:")
                for error in validationResult.errors {
                    Logger.debug("[ConfigStore]   - \(error.message)")
                }
                // Still load with warnings, but fail on errors
                return false
            }

            if validationResult.hasWarnings {
                Logger.debug("[ConfigStore] ⚠️ Configuration '\(name)' has validation warnings:")
                for warning in validationResult.warnings {
                    Logger.debug("[ConfigStore]   - \(warning.message)")
                }
            }

            applyLoadedConfiguration(config)
            currentConfigurationName = name
            preferences.setCurrentConfigName(name)

            // Start monitoring the configuration
            configFileManager.startMonitoring(configurationNamed: name)

            return true
        } catch {
            Logger.debug("[ConfigStore] Failed to load config '\(name)': \(error)")
            return false
        }
    }

    private func createEmptyConfiguration() {
        actions = []
        currentConfigurationName = "New Configuration"
        preferences.setCurrentConfigName("New Configuration")

        // Save the empty configuration
        saveConfiguration()
    }

    private func applyLoadedConfiguration(_ config: AppConfiguration) {
        // Build actions (actions is now an array, order is preserved)
        var loadedActions: [ActionConfig] = []
        for entry in config.actions {
            let action = entry.toActionConfig()
            loadedActions.append(action)
        }

        Logger.debug("[ConfigStore] Total loaded actions: \(loadedActions.count)")

        actions = AppConfigurationStore.applyTargetLanguage(
            loadedActions,
            targetLanguage: preferences.targetLanguage
        )
    }

    private func saveConfiguration(force: Bool = false) {
        // Skip if save is suspended (during reload)
        guard !isSaveSuspended else {
            Logger.debug("[ConfigStore] Save suspended, skipping")
            return
        }

        guard let configName = currentConfigurationName else {
            Logger.debug("[ConfigStore] No current configuration name set, skipping save")
            return
        }

        // Validate before saving (unless forcing)
        if !force {
            let validationResult = validateCurrentConfiguration()
            if validationResult.hasErrors {
                Logger.debug("[ConfigStore] ❌ Cannot save - validation errors:")
                for error in validationResult.errors {
                    Logger.debug("[ConfigStore]   - \(error.message)")
                }
                return
            }
        }

        let config = buildCurrentConfiguration()

        do {
            // Record timestamp before save
            lastSaveTimestamp = Date()

            try configFileManager.saveConfiguration(config, name: configName)
            Logger.debug("[ConfigStore] ✅ Saved configuration to '\(configName).json'")
        } catch {
            Logger.debug("[ConfigStore] ❌ Failed to save configuration: \(error)")
        }
    }

    private func buildCurrentConfiguration() -> AppConfiguration {
        // Build action entries (as array to preserve order)
        let actionEntries = actions.map { action in
            AppConfiguration.ActionEntry.from(action)
        }

        return AppConfiguration(
            version: "1.1.0",
            actions: actionEntries
        )
    }

    /// Reset to bundled default configuration (read-only mode)
    public func resetToDefault() {
        // Stop monitoring current config
        if let name = currentConfigurationName {
            configFileManager.stopMonitoring(configurationNamed: name)
        }

        if let name = currentConfigurationName {
            do {
                try configFileManager.deleteConfiguration(named: name)
            } catch {
                Logger.debug("[ConfigStore] ⚠️ Failed to delete configuration: \(error)")
            }
        }

        loadConfiguration()
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
