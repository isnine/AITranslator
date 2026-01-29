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

      // Use ConfigurationValidator for comprehensive validation
      let validationResult = ConfigurationValidator.shared.validate(config)

      // Only fail on errors, not warnings
      if validationResult.hasErrors {
        return .failure(.validationFailed(validationResult))
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
    print("[ConfigService] 🔄 Applying configuration: '\(configurationName ?? "unnamed")'")

    // Build actions (actions is now an array)
    var actions: [ActionConfig] = []
    for entry in config.actions {
      let action = entry.toActionConfig()
      actions.append(action)
    }
    print("[ConfigService]   - Loaded \(actions.count) actions")

    // IMPORTANT: Set configuration name BEFORE updating actions
    // This ensures the configuration is properly tracked
    if let name = configurationName {
      store.setCurrentConfigurationName(name)
      print("[ConfigService]   - Set configuration name: '\(name)'")
    } else {
      store.setCurrentConfigurationName(nil)
      print("[ConfigService]   - Set configuration name to nil")
    }

    // Apply actions directly (bypassing the default-mode check)
    store.applyActionsDirectly(actions)
    
    print("[ConfigService] ✅ Configuration applied successfully")
  }

  // MARK: - Private Helpers

  @MainActor
  private func buildAppConfiguration(
    from store: AppConfigurationStore,
    preferences: AppPreferences
  ) -> AppConfiguration {
    // Build action entries (as array to preserve order)
    let actionEntries = store.actions.map { action in
      AppConfiguration.ActionEntry.from(action)
    }

    return AppConfiguration(
      version: "1.0.0",
      actions: actionEntries
    )
  }

  private func encodeConfiguration(_ config: AppConfiguration) -> Data? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try? encoder.encode(config)
  }

  /// Validate configuration before saving
  /// Returns validation result with all issues found
  @MainActor
  public func validateCurrentConfiguration(
    from store: AppConfigurationStore,
    preferences: AppPreferences
  ) -> ConfigurationValidationResult {
    // First validate in-memory configuration
    let inMemoryResult = ConfigurationValidator.shared.validateInMemory(
      actions: store.actions
    )

    // Then build and validate the full configuration
    let config = buildAppConfiguration(from: store, preferences: preferences)
    let fullResult = ConfigurationValidator.shared.validate(config)

    // Combine issues (deduplicate if needed)
    let allIssues = inMemoryResult.issues + fullResult.issues.filter { issue in
      !inMemoryResult.issues.contains(issue)
    }

    return ConfigurationValidationResult(issues: allIssues)
  }
}

// MARK: - Errors

public enum ConfigurationError: LocalizedError, Sendable {
  case invalidData
  case decodingFailed(Error)
  case encodingFailed(Error)
  case unsupportedVersion(String)
  case validationFailed(ConfigurationValidationResult)
  case fileNotFound(name: String)
  case fileWriteFailed(Error)
  case fileReadFailed(Error)
  case bundledConfigNotFound

  public var errorDescription: String? {
    switch self {
    case .invalidData:
      return "Invalid configuration data"
    case .decodingFailed(let error):
      return "Failed to decode configuration: \(error.localizedDescription)"
    case .encodingFailed(let error):
      return "Failed to encode configuration: \(error.localizedDescription)"
    case .unsupportedVersion(let version):
      return "Unsupported configuration version: \(version)"
    case .validationFailed(let result):
      let errorMessages = result.errors.map(\.message).joined(separator: "; ")
      return "Configuration validation failed: \(errorMessages)"
    case .fileNotFound(let name):
      return "Configuration file not found: '\(name)'"
    case .fileWriteFailed(let error):
      return "Failed to write configuration file: \(error.localizedDescription)"
    case .fileReadFailed(let error):
      return "Failed to read configuration file: \(error.localizedDescription)"
    case .bundledConfigNotFound:
      return "Bundled default configuration not found in app bundle"
    }
  }
}
