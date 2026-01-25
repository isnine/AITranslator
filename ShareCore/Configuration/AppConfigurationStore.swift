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
    case tts(TTSConfiguration)
    case targetLanguage(TargetLanguageOption)
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

  /// Publisher to notify UI to reset pending changes (e.g., when user cancels creating custom config)
  public let resetPendingChangesPublisher = PassthroughSubject<Void, Never>()

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
  /// Custom configurations are disabled - changes are ignored
  @discardableResult
  public func updateActions(_ actions: [ActionConfig]) -> ConfigurationValidationResult? {
    // Custom configurations disabled - silently ignore changes
    print("[ConfigStore] ⚠️ Configuration changes are disabled")
    return nil
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
  /// Custom configurations are disabled - changes are ignored
  @discardableResult
  public func updateProviders(_ providers: [ProviderConfig]) -> ConfigurationValidationResult? {
    print("[ConfigStore] ⚠️ Configuration changes are disabled")
    return nil
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

    // Save enabledDeployments to UserDefaults for each provider
    for provider in providers {
      preferences.setEnabledDeployments(provider.enabledDeployments, for: provider.displayName)
      print("[ConfigStore] 💾 Saved enabledDeployments to UserDefaults for '\(provider.displayName)': \(provider.enabledDeployments)")
    }

    self.providers = providers
    saveConfiguration()

    return validationResult.issues.isEmpty ? nil : validationResult
  }

  /// Update TTS configuration
  /// Custom configurations are disabled - changes are ignored
  public func updateTTSConfiguration(_ ttsConfig: TTSConfiguration) {
    print("[ConfigStore] ⚠️ Configuration changes are disabled")
  }

  /// Internal method to actually apply TTS configuration update
  private func applyTTSConfigurationUpdate(_ ttsConfig: TTSConfiguration) {
    preferences.setTTSConfiguration(ttsConfig)
    saveConfiguration()
  }

  /// Update target language preference
  /// Custom configurations are disabled - changes are ignored
  public func updateTargetLanguage(_ option: TargetLanguageOption) {
    print("[ConfigStore] ⚠️ Configuration changes are disabled")
  }

  /// Internal method to actually apply target language update
  private func applyTargetLanguageUpdate(_ option: TargetLanguageOption) {
    preferences.setTargetLanguage(option)
    // Note: saveConfiguration will be triggered by the preferences.$targetLanguage subscription
  }

  /// Create a custom configuration from the current default configuration
  /// This copies the bundled default and switches to custom mode
  /// - Parameter name: The name for the new custom configuration
  /// - Returns: true if successful
  @discardableResult
  public func createCustomConfigurationFromDefault(named name: String = "My Configuration") -> Bool {
    // Custom configurations are disabled - always use bundled default
    print("[ConfigStore] ⚠️ Custom configurations are disabled")
    return false
  }

  /// Switch back to default configuration mode
  public func switchToDefaultConfiguration() {
    // Stop monitoring current config
    if let currentName = currentConfigurationName {
      configFileManager.stopMonitoring(configurationNamed: currentName)
    }

    loadBundledDefaultConfiguration()
    
    // Notify UI to sync from the new configuration
    configurationSwitchedPublisher.send()
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
  
  /// Set both configuration mode and name atomically
  /// This is used by ConfigurationService.applyConfiguration to ensure correct state
  public func setConfigurationModeAndName(_ mode: ConfigurationMode, name: String?) {
    let previousName = currentConfigurationName
    
    // Stop monitoring old config if different
    if let previousName, previousName != name {
      configFileManager.stopMonitoring(configurationNamed: previousName)
    }
    
    // Update mode and name
    self.configurationMode = mode
    self.currentConfigurationName = name
    preferences.setCurrentConfigName(name ?? Self.defaultConfigurationMarker)
    
    // Start monitoring new config if it's a custom config
    if let newName = name, !mode.isDefault {
      configFileManager.startMonitoring(configurationNamed: newName)
    }
    
    print("[ConfigStore] Mode set to: \(mode.displayName), name: \(name ?? "nil")")
  }
  
  /// Apply providers directly without triggering the default-mode check
  /// Used by ConfigurationService when loading a configuration
  public func applyProvidersDirectly(_ providers: [ProviderConfig]) {
    // Override enabledDeployments from UserDefaults for each provider
    var adjustedProviders: [ProviderConfig] = []
    for var provider in providers {
      if let storedEnabled = preferences.enabledDeployments(for: provider.displayName) {
        // Filter to only include deployments that still exist
        let validEnabled = storedEnabled.intersection(Set(provider.deployments))
        if !validEnabled.isEmpty {
          provider.enabledDeployments = validEnabled
        }
      }
      adjustedProviders.append(provider)
    }
    self.providers = adjustedProviders
    // Don't save - this is part of a load operation
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
    // Force all apps to use bundled default configuration (read-only mode)
    // Custom configurations are disabled to prevent user modifications
    print("[ConfigStore] 📦 Using bundled default configuration (read-only mode)")
    loadBundledDefaultConfiguration()
  }

  /// Special marker stored in preferences to indicate default configuration mode
  private static let defaultConfigurationMarker = "__DEFAULT__"

  /// Load the bundled default configuration directly from the app bundle (read-only)
  private func loadBundledDefaultConfiguration() {
    // Use ShareCore's bundle to find the configuration, not Bundle.main
    // This ensures it works in both the main app and extensions
    let shareCoreBundles = [
      Bundle(for: AppConfigurationStore.self),  // ShareCore framework bundle
      Bundle.main,  // Fallback to main bundle for main app
    ]
    
    var bundleURL: URL?
    for bundle in shareCoreBundles {
      if let url = bundle.url(forResource: "DefaultConfiguration", withExtension: "json") {
        bundleURL = url
        break
      }
    }
    
    guard let bundleURL else {
      print("[ConfigStore] ❌ Bundled default configuration not found in any bundle")
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

    // Use ShareCore's bundle first, then fallback to main bundle
    let shareCoreBundles = [
      Bundle(for: AppConfigurationStore.self),  // ShareCore framework bundle
      Bundle.main,  // Fallback to main bundle for main app
    ]
    
    var bundleURL: URL?
    for bundle in shareCoreBundles {
      if let url = bundle.url(forResource: "DefaultConfiguration", withExtension: "json") {
        bundleURL = url
        break
      }
    }
    
    guard let bundleURL else {
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
      if var provider = entry.toProviderConfig(name: name) {
        // Override enabledDeployments from UserDefaults if available
        if let storedEnabled = preferences.enabledDeployments(for: name) {
          // Filter to only include deployments that still exist
          let validEnabled = storedEnabled.intersection(Set(provider.deployments))
          if !validEnabled.isEmpty {
            provider.enabledDeployments = validEnabled
            print("[ConfigStore] ✅ Loaded enabledDeployments from UserDefaults for '\(name)': \(validEnabled)")
          }
        }
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
    // Custom configurations are disabled - always use bundled default
    print("[ConfigStore] ⚠️ Custom configurations are disabled")
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
