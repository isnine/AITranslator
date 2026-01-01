//
//  ConfigurationFileManager.swift
//  ShareCore
//
//  Created by AI Assistant on 2025/12/31.
//

import Foundation
import Combine
#if os(macOS)
import AppKit
#endif

/// Notification posted when a configuration file changes externally
public extension Notification.Name {
  static let configurationFileDidChange = Notification.Name("configurationFileDidChange")
}

/// Manages multiple configuration files stored in the App Group shared container
public final class ConfigurationFileManager: @unchecked Sendable {
  public static let shared = ConfigurationFileManager()

  private let fileManager = FileManager.default

  /// App Group identifier for shared container
  private static let appGroupIdentifier = "group.com.zanderwang.AITranslator"

  /// File monitoring sources keyed by file URL
  private var fileSources: [URL: DispatchSourceFileSystemObject] = [:]

  /// Lock for thread-safe access to fileSources
  private let sourcesLock = NSLock()

  /// Publisher for file change events
  public let fileChangePublisher = PassthroughSubject<ConfigurationFileChangeEvent, Never>()

  /// Publisher for configuration directory changes
  public let configDirectoryChangedPublisher = PassthroughSubject<Void, Never>()

  /// Cached custom directory URL
  private var cachedCustomDirectory: URL?

  /// Directory where configuration files are stored
  /// Priority: Custom Directory > iCloud > App Group > Application Support
  public var configurationsDirectory: URL {
    // 1. Check for custom directory from preferences
    if let customDir = AppPreferences.shared.customConfigDirectory {
      ensureDirectoryExists(customDir)
      return customDir
    }

    // 2. Check if iCloud is enabled and available
    if AppPreferences.shared.useICloudForConfig,
       let iCloudURL = AppPreferences.iCloudDocumentsURL {
      let configDir = iCloudURL.appendingPathComponent("Tree2Lang", isDirectory: true)
      ensureDirectoryExists(configDir)
      return configDir
    }

    // 3. Fallback to App Group shared container
    if let containerURL = fileManager.containerURL(
      forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
    ) {
      let configDir = containerURL.appendingPathComponent("Configurations", isDirectory: true)
      ensureDirectoryExists(configDir)
      return configDir
    }

    // 4. Final fallback to application support
    let appSupport = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!
    let configDir = appSupport.appendingPathComponent("Configurations", isDirectory: true)
    ensureDirectoryExists(configDir)
    return configDir
  }

  /// Returns the current storage location type
  public var currentStorageLocation: StorageLocation {
    if AppPreferences.shared.customConfigDirectory != nil {
      return .custom
    }
    if AppPreferences.shared.useICloudForConfig && AppPreferences.iCloudDocumentsURL != nil {
      return .iCloud
    }
    return .local
  }

  /// Storage location types
  public enum StorageLocation: String, CaseIterable {
    case local = "Local"
    case iCloud = "iCloud Drive"
    case custom = "Custom Folder"

    public var description: String {
      switch self {
      case .local:
        return "Stored in app container"
      case .iCloud:
        return "Synced across devices"
      case .custom:
        return "Custom folder location"
      }
    }

    public var icon: String {
      switch self {
      case .local:
        return "folder.fill"
      case .iCloud:
        return "icloud.fill"
      case .custom:
        return "folder.badge.gearshape"
      }
    }
  }

  private func ensureDirectoryExists(_ url: URL) {
    if !fileManager.fileExists(atPath: url.path) {
      try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
  }

  private init() {
    // Copy bundled default configuration on first run if no configs exist
    ensureBundledDefaultExists()
  }

  // MARK: - Storage Location Management

  /// Switch to iCloud storage
  /// - Parameter migrate: If true, migrate existing configurations to iCloud
  /// - Returns: Success status
  @discardableResult
  public func switchToICloud(migrate: Bool = true) -> Bool {
    guard AppPreferences.isICloudAvailable else {
      print("[ConfigFileManager] ❌ iCloud is not available")
      return false
    }

    let oldDirectory = configurationsDirectory

    // Clear custom directory first
    AppPreferences.shared.setCustomConfigDirectory(nil)

    // Enable iCloud
    AppPreferences.shared.setUseICloudForConfig(true)

    let newDirectory = configurationsDirectory

    if migrate && oldDirectory != newDirectory {
      migrateConfigurations(from: oldDirectory, to: newDirectory)
    }

    configDirectoryChangedPublisher.send()
    print("[ConfigFileManager] ✅ Switched to iCloud storage")
    return true
  }

  /// Switch to local storage
  /// - Parameter migrate: If true, migrate existing configurations to local
  public func switchToLocal(migrate: Bool = true) {
    let oldDirectory = configurationsDirectory

    // Clear custom directory and disable iCloud
    AppPreferences.shared.setCustomConfigDirectory(nil)
    AppPreferences.shared.setUseICloudForConfig(false)

    let newDirectory = configurationsDirectory

    if migrate && oldDirectory != newDirectory {
      migrateConfigurations(from: oldDirectory, to: newDirectory)
    }

    configDirectoryChangedPublisher.send()
    print("[ConfigFileManager] ✅ Switched to local storage")
  }

  /// Switch to a custom directory
  /// - Parameters:
  ///   - url: The custom directory URL
  ///   - migrate: If true, migrate existing configurations
  public func switchToCustomDirectory(_ url: URL, migrate: Bool = true) {
    let oldDirectory = configurationsDirectory

    // Disable iCloud and set custom directory
    AppPreferences.shared.setUseICloudForConfig(false)
    AppPreferences.shared.setCustomConfigDirectory(url)

    let newDirectory = configurationsDirectory

    if migrate && oldDirectory != newDirectory {
      migrateConfigurations(from: oldDirectory, to: newDirectory)
    }

    configDirectoryChangedPublisher.send()
    print("[ConfigFileManager] ✅ Switched to custom directory: \(url.path)")
  }

  /// Migrate configurations from one directory to another
  private func migrateConfigurations(from source: URL, to destination: URL) {
    ensureDirectoryExists(destination)

    guard let files = try? fileManager.contentsOfDirectory(
      at: source,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ) else {
      return
    }

    for file in files where file.pathExtension == "json" {
      let destFile = destination.appendingPathComponent(file.lastPathComponent)
      if !fileManager.fileExists(atPath: destFile.path) {
        try? fileManager.copyItem(at: file, to: destFile)
        print("[ConfigFileManager] Migrated: \(file.lastPathComponent)")
      }
    }
  }

  /// Reveal the configurations directory in Finder (macOS only)
  #if os(macOS)
  public func revealInFinder() {
    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: configurationsDirectory.path)
  }
  #endif

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

  /// Duplicate an existing configuration with a new name
  public func duplicateConfiguration(from sourceURL: URL) throws -> URL {
    let sourceConfig = try loadConfiguration(from: sourceURL)
    let sourceName = sourceURL.deletingPathExtension().lastPathComponent
    let newName = generateUniqueName(base: "\(sourceName) Copy")
    try saveConfiguration(sourceConfig, name: newName)
    return configurationsDirectory.appendingPathComponent("\(sanitizeFilename(newName)).json")
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

// MARK: - File Change Event

/// Represents a file change event for configuration files
public struct ConfigurationFileChangeEvent: Sendable {
  public enum ChangeType: Sendable {
    case modified
    case deleted
    case renamed
  }

  public let name: String
  public let url: URL
  public let changeType: ChangeType
  public let timestamp: Date

  public init(name: String, url: URL, changeType: ChangeType, timestamp: Date = Date()) {
    self.name = name
    self.url = url
    self.changeType = changeType
    self.timestamp = timestamp
  }
}

// MARK: - File Monitoring Extension

extension ConfigurationFileManager {
  /// Start monitoring a configuration file for external changes
  public func startMonitoring(configurationNamed name: String) {
    let sanitizedName = sanitizeFilename(name)
    let fileURL = configurationsDirectory.appendingPathComponent("\(sanitizedName).json")
    startMonitoring(url: fileURL)
  }

  /// Start monitoring a file URL for changes
  public func startMonitoring(url: URL) {
    sourcesLock.lock()
    defer { sourcesLock.unlock() }

    // Don't monitor if already monitoring
    guard fileSources[url] == nil else { return }

    let fileDescriptor = open(url.path, O_EVTONLY)
    guard fileDescriptor >= 0 else {
      print("[ConfigFileManager] Failed to open file for monitoring: \(url.path)")
      return
    }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fileDescriptor,
      eventMask: [.write, .delete, .rename, .extend],
      queue: DispatchQueue.global(qos: .utility)
    )

    source.setEventHandler { [weak self] in
      guard let self else { return }
      let flags = source.data
      let name = url.deletingPathExtension().lastPathComponent

      let changeType: ConfigurationFileChangeEvent.ChangeType
      if flags.contains(.delete) {
        changeType = .deleted
        // Stop monitoring deleted files
        self.stopMonitoring(url: url)
      } else if flags.contains(.rename) {
        changeType = .renamed
      } else {
        changeType = .modified
      }

      let event = ConfigurationFileChangeEvent(
        name: name,
        url: url,
        changeType: changeType
      )

      // Publish the event
      self.fileChangePublisher.send(event)

      // Also post a notification for backward compatibility
      NotificationCenter.default.post(
        name: .configurationFileDidChange,
        object: self,
        userInfo: ["event": event]
      )
    }

    source.setCancelHandler {
      close(fileDescriptor)
    }

    fileSources[url] = source
    source.resume()

    print("[ConfigFileManager] Started monitoring: \(url.lastPathComponent)")
  }

  /// Stop monitoring a specific file
  public func stopMonitoring(url: URL) {
    sourcesLock.lock()
    defer { sourcesLock.unlock() }

    if let source = fileSources.removeValue(forKey: url) {
      source.cancel()
      print("[ConfigFileManager] Stopped monitoring: \(url.lastPathComponent)")
    }
  }

  /// Stop monitoring a configuration by name
  public func stopMonitoring(configurationNamed name: String) {
    let sanitizedName = sanitizeFilename(name)
    let fileURL = configurationsDirectory.appendingPathComponent("\(sanitizedName).json")
    stopMonitoring(url: fileURL)
  }

  /// Stop all file monitoring
  public func stopAllMonitoring() {
    sourcesLock.lock()
    defer { sourcesLock.unlock() }

    for (_, source) in fileSources {
      source.cancel()
    }
    fileSources.removeAll()

    print("[ConfigFileManager] Stopped all file monitoring")
  }

  /// Check if a file is being monitored
  public func isMonitoring(url: URL) -> Bool {
    sourcesLock.lock()
    defer { sourcesLock.unlock() }
    return fileSources[url] != nil
  }

  /// Get the file URL for a configuration name
  public func configurationURL(forName name: String) -> URL {
    let sanitizedName = sanitizeFilename(name)
    return configurationsDirectory.appendingPathComponent("\(sanitizedName).json")
  }

  /// Check if a configuration file exists
  public func configurationExists(named name: String) -> Bool {
    let url = configurationURL(forName: name)
    return fileManager.fileExists(atPath: url.path)
  }

  /// Get the modification date of a configuration file
  public func modificationDate(forName name: String) -> Date? {
    let url = configurationURL(forName: name)
    let attributes = try? fileManager.attributesOfItem(atPath: url.path)
    return attributes?[.modificationDate] as? Date
  }
}
