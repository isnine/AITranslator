//
//  ConfigurationService.swift
//  ShareCore
//
//  Created by AI Assistant on 2025/12/31.
//

import Foundation

/// Service for importing and exporting app configuration as JSON
public final class ConfigurationService: Sendable {
  public static let shared = ConfigurationService()

  private init() {}

  // MARK: - Export

  /// Export current configuration to JSON data
  @MainActor
  public func exportConfiguration(
    from store: AppConfigurationStore,
    preferences: AppPreferences
  ) -> Data? {
    let config = buildAppConfiguration(from: store, preferences: preferences)
    return encodeConfiguration(config)
  }

  /// Export current configuration to a formatted JSON string
  @MainActor
  public func exportConfigurationString(
    from store: AppConfigurationStore,
    preferences: AppPreferences
  ) -> String? {
    guard let data = exportConfiguration(from: store, preferences: preferences) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  // MARK: - Import

  /// Import configuration from JSON data
  public func importConfiguration(
    from data: Data
  ) -> Result<AppConfiguration, ConfigurationError> {
    do {
      let decoder = JSONDecoder()
      let config = try decoder.decode(AppConfiguration.self, from: data)

      // Validate version
      guard isVersionSupported(config.version) else {
        return .failure(.unsupportedVersion(config.version))
      }

      // Validate providers exist for actions
      let validationResult = validateConfiguration(config)
      if case .failure(let error) = validationResult {
        return .failure(error)
      }

      return .success(config)
    } catch {
      return .failure(.decodingFailed(error))
    }
  }

  /// Import configuration from JSON string
  public func importConfiguration(
    from jsonString: String
  ) -> Result<AppConfiguration, ConfigurationError> {
    guard let data = jsonString.data(using: .utf8) else {
      return .failure(.invalidData)
    }
    return importConfiguration(from: data)
  }

  /// Apply imported configuration to the app
  @MainActor
  public func applyConfiguration(
    _ config: AppConfiguration,
    to store: AppConfigurationStore,
    preferences: AppPreferences,
    configurationName: String? = nil
  ) {
    // Apply preferences
    if let prefsConfig = config.preferences {
      if let targetLang = prefsConfig.targetLanguage,
         let option = TargetLanguageOption(rawValue: targetLang) {
        preferences.setTargetLanguage(option)
      }
      // Hotkey is platform-specific, handled separately
    }

    // Apply TTS
    if let ttsEntry = config.tts {
      if let usesDefault = ttsEntry.useDefault {
        preferences.setTTSUsesDefaultConfiguration(usesDefault)
      }
      if let ttsConfig = ttsEntry.toTTSConfiguration() {
        preferences.setTTSConfiguration(ttsConfig)
      }
    }

    // Build provider map (name -> UUID)
    var providers: [ProviderConfig] = []
    var providerNameToID: [String: UUID] = [:]

    for (name, entry) in config.providers {
      if let provider = entry.toProviderConfig(name: name) {
        providers.append(provider)
        providerNameToID[name] = provider.id
      }
    }

    // Build actions
    var actions: [ActionConfig] = []
    for (name, entry) in config.actions {
      let action = entry.toActionConfig(name: name, providerMap: providerNameToID)
      actions.append(action)
    }

    // Apply to store
    store.updateProviders(providers)
    store.updateActions(actions)
    
    // Set current configuration name
    store.setCurrentConfigurationName(configurationName)
  }

  // MARK: - Private Helpers

  @MainActor
  private func buildAppConfiguration(
    from store: AppConfigurationStore,
    preferences: AppPreferences
  ) -> AppConfiguration {
    // Build provider entries and name map
    var providerEntries: [String: AppConfiguration.ProviderEntry] = [:]
    var providerIDToName: [UUID: String] = [:]

    for provider in store.providers {
      let (name, entry) = AppConfiguration.ProviderEntry.from(provider)
      // Handle duplicate names by appending suffix
      var uniqueName = name
      var counter = 1
      while providerEntries[uniqueName] != nil {
        counter += 1
        uniqueName = "\(name) \(counter)"
      }
      providerEntries[uniqueName] = entry
      providerIDToName[provider.id] = uniqueName
    }

    // Build action entries
    var actionEntries: [String: AppConfiguration.ActionEntry] = [:]
    for action in store.actions {
      let (name, entry) = AppConfiguration.ActionEntry.from(action, providerNames: providerIDToName)
      // Handle duplicate names
      var uniqueName = name
      var counter = 1
      while actionEntries[uniqueName] != nil {
        counter += 1
        uniqueName = "\(name) \(counter)"
      }
      actionEntries[uniqueName] = entry
    }

    // Build preferences
    let prefsConfig = AppConfiguration.PreferencesConfig(
      targetLanguage: preferences.targetLanguage.rawValue
    )

    // Build TTS
    let ttsEntry = AppConfiguration.TTSEntry.from(
      preferences.effectiveTTSConfiguration,
      usesDefault: preferences.ttsUsesDefaultConfiguration
    )

    return AppConfiguration(
      version: "1.0.0",
      preferences: prefsConfig,
      providers: providerEntries,
      tts: ttsEntry,
      actions: actionEntries
    )
  }

  private func encodeConfiguration(_ config: AppConfiguration) -> Data? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try? encoder.encode(config)
  }

  private func isVersionSupported(_ version: String) -> Bool {
    // Support version 1.x.x
    let components = version.split(separator: ".").compactMap { Int($0) }
    guard let major = components.first else { return false }
    return major == 1
  }

  private func validateConfiguration(
    _ config: AppConfiguration
  ) -> Result<Void, ConfigurationError> {
    let providerNames = Set(config.providers.keys)

    for (actionName, action) in config.actions {
      for providerName in action.providers {
        if !providerNames.contains(providerName) {
          return .failure(.missingProvider(providerName, inAction: actionName))
        }
      }
    }

    return .success(())
  }
}

// MARK: - Errors

public enum ConfigurationError: LocalizedError, Sendable {
  case invalidData
  case decodingFailed(Error)
  case unsupportedVersion(String)
  case missingProvider(String, inAction: String)

  public var errorDescription: String? {
    switch self {
    case .invalidData:
      return "Invalid configuration data"
    case .decodingFailed(let error):
      return "Failed to decode configuration: \(error.localizedDescription)"
    case .unsupportedVersion(let version):
      return "Unsupported configuration version: \(version)"
    case .missingProvider(let provider, let action):
      return "Action '\(action)' references unknown provider '\(provider)'"
    }
  }
}
