//
//  ConfigurationFileManager.swift
//  ShareCore
//
//  Created by AI Assistant on 2025/12/31.
//

import Foundation

/// Manages multiple configuration files stored in the App Group shared container
public final class ConfigurationFileManager: Sendable {
  public static let shared = ConfigurationFileManager()

  private let fileManager = FileManager.default

  /// App Group identifier for shared container
  private static let appGroupIdentifier = "group.com.zanderwang.AITranslator"

  /// Directory where configuration files are stored (App Group shared container)
  public var configurationsDirectory: URL {
    guard let containerURL = fileManager.containerURL(
      forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
    ) else {
      // Fallback to application support if App Group is unavailable
      let appSupport = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first!
      return appSupport.appendingPathComponent("Configurations", isDirectory: true)
    }

    let configDir = containerURL.appendingPathComponent("Configurations", isDirectory: true)

    if !fileManager.fileExists(atPath: configDir.path) {
      try? fileManager.createDirectory(at: configDir, withIntermediateDirectories: true)
    }

    return configDir
  }

  private init() {
    // Copy bundled default configuration on first run if no configs exist
    ensureBundledDefaultExists()
  }

  /// Ensure the bundled default configuration is copied to the configurations directory on first run
  private func ensureBundledDefaultExists() {
    let defaultConfigURL = configurationsDirectory.appendingPathComponent("Default.json")
    
    // Only copy if it doesn't exist yet
    guard !fileManager.fileExists(atPath: defaultConfigURL.path) else { return }
    
    // Find and copy bundled default
    guard let bundleURL = Bundle.main.url(forResource: "DefaultConfiguration", withExtension: "json") else {
      return
    }
    
    do {
      try fileManager.copyItem(at: bundleURL, to: defaultConfigURL)
    } catch {
      print("Failed to copy bundled default configuration: \(error)")
    }
  }

  /// List all saved configuration files
  public func listConfigurations() -> [ConfigurationFileInfo] {
    // Ensure bundled default is present
    ensureBundledDefaultExists()
    
    guard let files = try? fileManager.contentsOfDirectory(
      at: configurationsDirectory,
      includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    return files
      .filter { $0.pathExtension == "json" }
      .compactMap { url -> ConfigurationFileInfo? in
        let name = url.deletingPathExtension().lastPathComponent
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let modifiedDate = attributes?[.modificationDate] as? Date ?? Date()
        return ConfigurationFileInfo(name: name, url: url, modifiedDate: modifiedDate)
      }
      .sorted { $0.modifiedDate > $1.modifiedDate }
  }

  /// Save a configuration with the given name
  public func saveConfiguration(
    _ config: AppConfiguration,
    name: String
  ) throws {
    let sanitizedName = sanitizeFilename(name)
    let fileURL = configurationsDirectory.appendingPathComponent("\(sanitizedName).json")

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(config)
    try data.write(to: fileURL)
  }

  /// Load a configuration from the given URL
  public func loadConfiguration(from url: URL) throws -> AppConfiguration {
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    return try decoder.decode(AppConfiguration.self, from: data)
  }

  /// Load a configuration by name
  public func loadConfiguration(named name: String) throws -> AppConfiguration {
    let sanitizedName = sanitizeFilename(name)
    let fileURL = configurationsDirectory.appendingPathComponent("\(sanitizedName).json")
    return try loadConfiguration(from: fileURL)
  }

  /// Delete a configuration file
  public func deleteConfiguration(at url: URL) throws {
    try fileManager.removeItem(at: url)
  }

  /// Delete a configuration by name
  public func deleteConfiguration(named name: String) throws {
    let sanitizedName = sanitizeFilename(name)
    let fileURL = configurationsDirectory.appendingPathComponent("\(sanitizedName).json")
    try fileManager.removeItem(at: fileURL)
  }

  /// Create and save the default configuration template
  @MainActor
  public func createDefaultTemplate(
    from store: AppConfigurationStore,
    preferences: AppPreferences
  ) throws -> URL {
    guard let data = ConfigurationService.shared.exportConfiguration(
      from: store,
      preferences: preferences
    ) else {
      throw ConfigurationError.invalidData
    }

    let config = try JSONDecoder().decode(AppConfiguration.self, from: data)
    let name = generateUniqueName(base: "Default Template")
    try saveConfiguration(config, name: name)

    return configurationsDirectory.appendingPathComponent("\(sanitizeFilename(name)).json")
  }

  /// Create an empty configuration template
  public func createEmptyTemplate() throws -> URL {
    let emptyConfig = AppConfiguration(
      version: "1.0.0",
      preferences: AppConfiguration.PreferencesConfig(
        targetLanguage: "Simplified Chinese",
        hotkey: AppConfiguration.HotkeyConfig(
          key: "Space",
          modifiers: ["command", "shift"]
        )
      ),
      providers: [:],
      tts: nil,
      actions: []
    )

    let name = generateUniqueName(base: "Empty Template")
    try saveConfiguration(emptyConfig, name: name)

    return configurationsDirectory.appendingPathComponent("\(sanitizeFilename(name)).json")
  }

  /// Generate a unique name if the base name already exists
  private func generateUniqueName(base: String) -> String {
    let existingNames = Set(listConfigurations().map { $0.name })

    if !existingNames.contains(base) {
      return base
    }

    var counter = 1
    var candidate = "\(base) \(counter)"
    while existingNames.contains(candidate) {
      counter += 1
      candidate = "\(base) \(counter)"
    }

    return candidate
  }

  /// Sanitize a filename to remove invalid characters
  private func sanitizeFilename(_ name: String) -> String {
    let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
    return name
      .components(separatedBy: invalidCharacters)
      .joined()
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

// MARK: - Configuration File Info

public struct ConfigurationFileInfo: Identifiable, Sendable {
  public let id: URL
  public let name: String
  public let url: URL
  public let modifiedDate: Date

  public init(name: String, url: URL, modifiedDate: Date) {
    self.id = url
    self.name = name
    self.url = url
    self.modifiedDate = modifiedDate
  }

  public var formattedDate: String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: modifiedDate, relativeTo: Date())
  }
}
