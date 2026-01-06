//
//  AppConfigurationStore.swift
//  ShareCore
//
//  Created by Codex on 2025/10/19.
//

import Foundation
import Combine

// MARK: - Configuration Mode

/// Represents the current configuration mode
public enum ConfigurationMode: Sendable, Equatable {
  /// Using the bundled default configuration (read-only)
  case defaultConfiguration
  /// Using a user-created custom configuration (editable)
  case customConfiguration(name: String)

  public var isDefault: Bool {
    if case .defaultConfiguration = self { return true }
    return false
  }

  public var displayName: String {
    switch self {
    case .defaultConfiguration:
      return NSLocalizedString(
        "Default Configuration",
        comment: "Name shown when using default configuration"
      )
    case .customConfiguration(let name):
      return name
    }
  }
}

/// Request to create a custom configuration with pending changes
public struct CreateCustomConfigurationRequest {
  public enum ChangeType {
    case actions([ActionConfig])
    case providers([ProviderConfig])
  }

  public let changeType: ChangeType
  public let completion: @MainActor (Bool) -> Void

  public init(changeType: ChangeType, completion: @escaping @MainActor (Bool) -> Void) {
    self.changeType = changeType
    self.completion = completion
  }
}

@MainActor
public final class AppConfigurationStore: ObservableObject {
  public static let shared = AppConfigurationStore()

  @Published public private(set) var actions: [ActionConfig]
  @Published public private(set) var providers: [ProviderConfig]
  @Published public private(set) var currentConfigurationName: String?

  /// The current configuration mode (default or custom)
  @Published public private(set) var configurationMode: ConfigurationMode = .defaultConfiguration

  /// Publisher for requesting creation of custom configuration
  /// UI should subscribe to this to show confirmation dialog
  public let createCustomConfigurationRequestPublisher = PassthroughSubject<CreateCustomConfigurationRequest, Never>()

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
    self.lastValidationResult = nil

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
      print("[ConfigStore] Ignoring file change - self-initiated save")
      return
    }

    switch event.changeType {
    case .modified:
      print("[ConfigStore] 🔄 External file modification detected, reloading...")
      reloadCurrentConfiguration()

    case .deleted:
      print("[ConfigStore] ⚠️ Configuration file deleted externally")
      // Try to switch to another available configuration
      let availableConfigs = configFileManager.listConfigurations()
      if let firstConfig = availableConfigs.first {
        _ = switchConfiguration(to: firstConfig.name)
      } else {
        createEmptyConfiguration()
      }

    case .renamed:
      print("[ConfigStore] ⚠️ Configuration file renamed externally")
      // Try to find the file under a new name or reload
      reloadCurrentConfiguration()
    }
  }

  // MARK: - Public Methods

  /// Update actions with validation
  /// Returns validation result (nil if validation passed or was skipped)
  /// In default configuration mode, this will trigger a request to create custom configuration
  @discardableResult
  public func updateActions(_ actions: [ActionConfig]) -> ConfigurationValidationResult? {
    // If using default configuration, request user to create custom configuration first
    if configurationMode.isDefault {
      let request = CreateCustomConfigurationRequest(changeType: .actions(actions)) { [weak self] created in
        guard let self, created else { return }
        // User confirmed, apply changes after switching to custom configuration
        _ = self.applyActionsUpdate(actions)
      }
      createCustomConfigurationRequestPublisher.send(request)
      return nil
    }

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
      actions: adjusted,
      providers: providers
    )

    self.lastValidationResult = validationResult

    // Apply changes even with warnings, but log them
    if validationResult.hasWarnings {
      for warning in validationResult.warnings {
        print("[ConfigStore] ⚠️ Validation warning: \(warning.message)")
      }
    }

    self.actions = adjusted
    saveConfiguration()

    return validationResult.issues.isEmpty ? nil : validationResult
  }

  /// Update providers with validation
  /// Returns validation result (nil if validation passed or was skipped)
  /// In default configuration mode, this will trigger a request to create custom configuration
  @discardableResult
  public func updateProviders(_ providers: [ProviderConfig]) -> ConfigurationValidationResult? {
    // If using default configuration, request user to create custom configuration first
    if configurationMode.isDefault {
      let request = CreateCustomConfigurationRequest(changeType: .providers(providers)) { [weak self] created in
        guard let self, created else { return }
        // User confirmed, apply changes after switching to custom configuration
        _ = self.applyProvidersUpdate(providers)
      }
      createCustomConfigurationRequestPublisher.send(request)
      return nil
    }

    return applyProvidersUpdate(providers)
  }

  /// Internal method to actually apply providers update
  private func applyProvidersUpdate(_ providers: [ProviderConfig]) -> ConfigurationValidationResult? {
    // Validate before applying
    let validationResult = ConfigurationValidator.shared.validateInMemory(
      actions: actions,
      providers: providers
    )

    self.lastValidationResult = validationResult

    // Apply changes even with warnings, but log them
    if validationResult.hasWarnings {
      for warning in validationResult.warnings {
        print("[ConfigStore] ⚠️ Validation warning: \(warning.message)")
      }
    }

    self.providers = providers
    saveConfiguration()

    return validationResult.issues.isEmpty ? nil : validationResult
  }

  /// Create a custom configuration from the current default configuration
  /// This copies the bundled default and switches to custom mode
  /// - Parameter name: The name for the new custom configuration
  /// - Returns: true if successful
  @discardableResult
  public func createCustomConfigurationFromDefault(named name: String = "My Configuration") -> Bool {
    guard configurationMode.isDefault else {
      print("[ConfigStore] Already using custom configuration")
      return true
    }

    // Build current configuration from in-memory state
    let config = buildCurrentConfiguration()

    do {
      // Save to a new file
      try configFileManager.saveConfiguration(config, name: name)

      // Switch to custom mode
      self.configurationMode = .customConfiguration(name: name)
      self.currentConfigurationName = name
      preferences.setCurrentConfigName(name)

      // Start monitoring the new file
      configFileManager.startMonitoring(configurationNamed: name)

      print("[ConfigStore] ✅ Created custom configuration: '\(name)'")
      return true
    } catch {
      print("[ConfigStore] ❌ Failed to create custom configuration: \(error)")
      return false
    }
  }

  /// Switch back to default configuration mode
  public func switchToDefaultConfiguration() {
    // Stop monitoring current config
    if let currentName = currentConfigurationName {
      configFileManager.stopMonitoring(configurationNamed: currentName)
    }

    loadBundledDefaultConfiguration()
  }

  public func setCurrentConfigurationName(_ name: String?) {
    let previousName = currentConfigurationName
    guard previousName != name else { return }

    // Update file monitoring for the old config
    if let previousName {
      configFileManager.stopMonitoring(configurationNamed: previousName)
    }

    self.currentConfigurationName = name
    preferences.setCurrentConfigName(name)

    // Start monitoring the new config
    if let newName = name {
      configFileManager.startMonitoring(configurationNamed: newName)
    }
  }

  /// Reload the current configuration from disk
  public func reloadCurrentConfiguration() {
    guard let name = currentConfigurationName else { return }

    // Suspend auto-save during reload to prevent loops
    isSaveSuspended = true
    defer { isSaveSuspended = false }

    if tryLoadConfiguration(named: name) {
      print("[ConfigStore] ✅ Reloaded configuration: '\(name)'")
    } else {
      print("[ConfigStore] ❌ Failed to reload configuration: '\(name)'")
    }
  }

  /// Validate current in-memory configuration
  public func validateCurrentConfiguration() -> ConfigurationValidationResult {
    let result = ConfigurationValidator.shared.validateInMemory(
      actions: actions,
      providers: providers
    )
    self.lastValidationResult = result
    return result
  }

  /// Force save current configuration (bypassing validation errors)
  public func forceSaveConfiguration() {
    saveConfiguration(force: true)
  }

  // MARK: - Persistence using ConfigurationFileManager

  private func loadConfiguration() {
    // Step 1: Read current config name from UserDefaults
    // A nil or empty name means we should use default configuration mode
    let storedName = preferences.currentConfigName
    print("[ConfigStore] Stored config name from UserDefaults: \(storedName ?? "nil")")

    // Step 2: Check if we should use default configuration mode
    // Use default mode if: no stored name, or stored name is the special marker
    if storedName == nil || storedName == Self.defaultConfigurationMarker {
      print("[ConfigStore] 📦 Using bundled default configuration (read-only mode)")
      loadBundledDefaultConfiguration()
      return
    }

    // Step 3: Try to load the named custom configuration
    if let name = storedName {
      if tryLoadConfiguration(named: name) {
        print("[ConfigStore] ✅ Successfully loaded custom config: '\(name)'")
        configurationMode = .customConfiguration(name: name)
        configFileManager.startMonitoring(configurationNamed: name)
        return
      }
      print("[ConfigStore] ⚠️ Failed to load stored config '\(name)', falling back to default...")
    }

    // Step 4: Fallback to bundled default configuration
    print("[ConfigStore] 📦 Falling back to bundled default configuration")
    loadBundledDefaultConfiguration()
  }

  /// Special marker stored in preferences to indicate default configuration mode
  private static let defaultConfigurationMarker = "__DEFAULT__"

  /// Load the bundled default configuration directly from the app bundle (read-only)
  private func loadBundledDefaultConfiguration() {
    guard let bundleURL = Bundle.main.url(forResource: "DefaultConfiguration", withExtension: "json") else {
      print("[ConfigStore] ❌ Bundled default configuration not found in app bundle")
      createEmptyConfiguration()
      return
    }

    do {
      let config = try configFileManager.loadConfiguration(from: bundleURL)

      // Validate before applying
      let validationResult = ConfigurationValidator.shared.validate(config)
      self.lastValidationResult = validationResult

      if validationResult.hasErrors {
        print("[ConfigStore] ❌ Bundled default configuration has validation errors")
        createEmptyConfiguration()
        return
      }

      applyLoadedConfiguration(config)

      // Set to default configuration mode
      self.configurationMode = .defaultConfiguration
      self.currentConfigurationName = nil
      preferences.setCurrentConfigName(Self.defaultConfigurationMarker)

      // Apply preferences if present
      if let prefsConfig = config.preferences {
        if let targetLang = prefsConfig.targetLanguage,
           let option = TargetLanguageOption(rawValue: targetLang) {
          preferences.setTargetLanguage(option)
        }
      }

      // Apply TTS if present
      if let ttsEntry = config.tts {
        let ttsConfig = ttsEntry.toTTSConfiguration()
        preferences.setTTSConfiguration(ttsConfig)
      }

      print("[ConfigStore] ✅ Loaded bundled default configuration (read-only mode)")
    } catch {
      print("[ConfigStore] ❌ Failed to load bundled default configuration: \(error)")
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

  /// Load the bundled default configuration and create a custom "Default" configuration from it
  /// This is used when an existing configuration has an incompatible version
  private func loadAndSwitchToDefault() -> Bool {
    // First, copy the bundled default to configurations directory (overwriting existing)
    let defaultConfigURL = configFileManager.configurationsDirectory.appendingPathComponent("Default.json")

    guard let bundleURL = Bundle.main.url(forResource: "DefaultConfiguration", withExtension: "json") else {
      print("[ConfigStore] ❌ Bundled default configuration not found")
      return false
    }

    do {
      // Remove existing Default.json if present
      if FileManager.default.fileExists(atPath: defaultConfigURL.path) {
        try FileManager.default.removeItem(at: defaultConfigURL)
      }
      // Copy bundled default
      try FileManager.default.copyItem(at: bundleURL, to: defaultConfigURL)
      print("[ConfigStore] ✅ Copied bundled default configuration to Default.json")
    } catch {
      print("[ConfigStore] ❌ Failed to copy bundled default: \(error)")
      return false
    }

    // Load the default configuration directly
    do {
      let config = try configFileManager.loadConfiguration(named: "Default")
      
      // Validate before applying
      let validationResult = ConfigurationValidator.shared.validate(config)
      self.lastValidationResult = validationResult

      if validationResult.hasErrors {
        print("[ConfigStore] ❌ Default configuration has validation errors")
        return false
      }

      applyLoadedConfiguration(config)
      
      // This creates a custom configuration named "Default" (not the read-only default mode)
      self.configurationMode = .customConfiguration(name: "Default")
      self.currentConfigurationName = "Default"
      preferences.setCurrentConfigName("Default")
      
      // Apply preferences if present
      if let prefsConfig = config.preferences {
        if let targetLang = prefsConfig.targetLanguage,
           let option = TargetLanguageOption(rawValue: targetLang) {
          preferences.setTargetLanguage(option)
        }
      }

      // Apply TTS if present
      if let ttsEntry = config.tts {
        let ttsConfig = ttsEntry.toTTSConfiguration()
        preferences.setTTSConfiguration(ttsConfig)
      }

      configFileManager.startMonitoring(configurationNamed: "Default")
      print("[ConfigStore] ✅ Created custom 'Default' configuration from bundled default")
      return true
    } catch {
      print("[ConfigStore] ❌ Failed to load default configuration: \(error)")
      return false
    }
  }

  private func tryLoadConfiguration(named name: String) -> Bool {
    do {
      let config = try configFileManager.loadConfiguration(named: name)

      // Check version compatibility - require 1.1.0 or higher
      if !isVersionCompatible(config.version) {
        print("[ConfigStore] ⚠️ Configuration '\(name)' has incompatible version: \(config.version)")
        print("[ConfigStore] 🔄 Will load default configuration with version 1.1.0")
        return loadAndSwitchToDefault()
      }

      // Validate the loaded configuration
      let validationResult = ConfigurationValidator.shared.validate(config)
      self.lastValidationResult = validationResult

      if validationResult.hasErrors {
        print("[ConfigStore] ❌ Configuration '\(name)' has validation errors:")
        for error in validationResult.errors {
          print("[ConfigStore]   - \(error.message)")
        }
        // Still load with warnings, but fail on errors
        return false
      }

      if validationResult.hasWarnings {
        print("[ConfigStore] ⚠️ Configuration '\(name)' has validation warnings:")
        for warning in validationResult.warnings {
          print("[ConfigStore]   - \(warning.message)")
        }
      }

      applyLoadedConfiguration(config)
      self.currentConfigurationName = name
      preferences.setCurrentConfigName(name)

      // Apply preferences if present
      if let prefsConfig = config.preferences {
        if let targetLang = prefsConfig.targetLanguage,
          let option = TargetLanguageOption(rawValue: targetLang)
        {
          preferences.setTargetLanguage(option)
        }
      }

      // Apply TTS if present
      if let ttsEntry = config.tts {
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
    var providerDeploymentsMap: [String: (id: UUID, deployments: [String])] = [:]

    print("[ConfigStore] Parsing \(config.providers.count) providers from config")

    for (name, entry) in config.providers {
      print("[ConfigStore] Trying to parse provider: '\(name)' with category: '\(entry.category)'")
      if let provider = entry.toProviderConfig(name: name) {
        loadedProviders.append(provider)
        providerNameToID[name] = provider.id
        providerDeploymentsMap[name] = (id: provider.id, deployments: provider.deployments)
        print("[ConfigStore] ✅ Successfully parsed provider: '\(name)'")
      } else {
        print("[ConfigStore] ❌ Failed to parse provider: '\(name)' - toProviderConfig returned nil")
      }
    }

    print("[ConfigStore] Total loaded providers: \(loadedProviders.count)")

    // Build actions (actions is now an array, order is preserved)
    var loadedActions: [ActionConfig] = []
    for entry in config.actions {
      let action = entry.toActionConfig()
      loadedActions.append(action)
    }

    print("[ConfigStore] Total loaded actions: \(loadedActions.count)")

    self.providers = loadedProviders
    self.actions = AppConfigurationStore.applyTargetLanguage(
      loadedActions,
      targetLanguage: preferences.targetLanguage
    )
  }

  private func saveConfiguration(force: Bool = false) {
    // Skip if save is suspended (during reload)
    guard !isSaveSuspended else {
      print("[ConfigStore] Save suspended, skipping")
      return
    }

    // Skip saving in default configuration mode (read-only)
    guard !configurationMode.isDefault else {
      print("[ConfigStore] Using default configuration (read-only), skipping save")
      return
    }

    guard let configName = currentConfigurationName else {
      print("[ConfigStore] No current configuration name set, skipping save")
      return
    }

    // Validate before saving (unless forcing)
    if !force {
      let validationResult = validateCurrentConfiguration()
      if validationResult.hasErrors {
        print("[ConfigStore] ❌ Cannot save - validation errors:")
        for error in validationResult.errors {
          print("[ConfigStore]   - \(error.message)")
        }
        return
      }
    }

    let config = buildCurrentConfiguration()

    do {
      // Record timestamp before save
      lastSaveTimestamp = Date()

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
      AppConfiguration.ActionEntry.from(action)
    }

    return AppConfiguration(
      version: "1.1.0",
      preferences: AppConfiguration.PreferencesConfig(
        targetLanguage: preferences.targetLanguage.rawValue
      ),
      providers: providerEntries,
      tts: AppConfiguration.TTSEntry.from(
        preferences.ttsConfiguration
      ),
      actions: actionEntries
    )
  }

  /// Reset to bundled default configuration (read-only mode)
  public func resetToDefault() {
    // Stop monitoring current config
    if let name = currentConfigurationName {
      configFileManager.stopMonitoring(configurationNamed: name)
    }

    // Switch to bundled default configuration (read-only mode)
    print("[ConfigStore] 📦 Resetting to bundled default configuration")
    switchToDefaultConfiguration()
  }

  /// Switch to a different configuration by name
  public func switchConfiguration(to name: String) -> Bool {
    // Stop monitoring current config
    if let currentName = currentConfigurationName {
      configFileManager.stopMonitoring(configurationNamed: currentName)
    }

    if tryLoadConfiguration(named: name) {
      print("[ConfigStore] ✅ Switched to configuration: '\(name)'")
      configurationMode = .customConfiguration(name: name)
      configFileManager.startMonitoring(configurationNamed: name)
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
