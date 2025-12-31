//
//  AppConfiguration.swift
//  ShareCore
//
//  Created by AI Assistant on 2025/12/31.
//

import Foundation

/// Root configuration structure for import/export
public struct AppConfiguration: Codable, Sendable {
  public var version: String
  public var preferences: PreferencesConfig?
  public var providers: [String: ProviderEntry]
  public var tts: TTSEntry?
  public var actions: [String: ActionEntry]

  public init(
    version: String = "1.0.0",
    preferences: PreferencesConfig? = nil,
    providers: [String: ProviderEntry] = [:],
    tts: TTSEntry? = nil,
    actions: [String: ActionEntry] = [:]
  ) {
    self.version = version
    self.preferences = preferences
    self.providers = providers
    self.tts = tts
    self.actions = actions
  }
}

// MARK: - Preferences

public extension AppConfiguration {
  struct PreferencesConfig: Codable, Sendable {
    public var targetLanguage: String?
    public var hotkey: HotkeyConfig?

    public init(targetLanguage: String? = nil, hotkey: HotkeyConfig? = nil) {
      self.targetLanguage = targetLanguage
      self.hotkey = hotkey
    }
  }

  struct HotkeyConfig: Codable, Sendable {
    public var key: String
    public var modifiers: [String]

    public init(key: String, modifiers: [String]) {
      self.key = key
      self.modifiers = modifiers
    }
  }
}

// MARK: - Provider

public extension AppConfiguration {
  struct ProviderEntry: Codable, Sendable {
    public var category: String
    public var model: String?
    public var endpoint: String
    public var authHeader: String?
    public var token: String

    public init(
      category: String,
      model: String? = nil,
      endpoint: String,
      authHeader: String? = nil,
      token: String
    ) {
      self.category = category
      self.model = model
      self.endpoint = endpoint
      self.authHeader = authHeader
      self.token = token
    }

    /// Convert to internal ProviderConfig
    public func toProviderConfig(name: String) -> ProviderConfig? {
      guard let url = URL(string: endpoint) else {
        print("[ProviderEntry] ❌ Invalid URL: '\(endpoint)'")
        return nil
      }
      
      print("[ProviderEntry] Looking for category: '\(category)'")
      print("[ProviderEntry] Available categories: \(ProviderCategory.allCases.map { "'\($0.rawValue)'" }.joined(separator: ", "))")
      
      guard let providerCategory = ProviderCategory(rawValue: category)
        ?? ProviderCategory.allCases.first(where: { $0.displayName == category }) else {
        print("[ProviderEntry] ❌ Unknown category: '\(category)'")
        return nil
      }
      
      print("[ProviderEntry] ✅ Matched category: \(providerCategory.rawValue)")

      let resolvedAuthHeader: String
      if let authHeader, !authHeader.isEmpty {
        resolvedAuthHeader = authHeader
      } else {
        resolvedAuthHeader = providerCategory == .azureOpenAI ? "api-key" : "Authorization"
      }

      return ProviderConfig(
        displayName: name,
        apiURL: url,
        token: token,
        authHeaderName: resolvedAuthHeader,
        category: providerCategory,
        modelName: model
      )
    }

    /// Create from internal ProviderConfig
    public static func from(_ config: ProviderConfig) -> (name: String, entry: ProviderEntry) {
      let entry = ProviderEntry(
        category: config.category.rawValue,
        model: config.modelName,
        endpoint: config.apiURL.absoluteString,
        authHeader: config.authHeaderName,
        token: config.token
      )
      return (config.displayName, entry)
    }
  }
}

// MARK: - TTS

public extension AppConfiguration {
  struct TTSEntry: Codable, Sendable {
    public var useDefault: Bool?
    public var endpoint: String?
    public var apiKey: String?
    public var model: String?
    public var voice: String?

    public init(
      useDefault: Bool? = nil,
      endpoint: String? = nil,
      apiKey: String? = nil,
      model: String? = nil,
      voice: String? = nil
    ) {
      self.useDefault = useDefault
      self.endpoint = endpoint
      self.apiKey = apiKey
      self.model = model
      self.voice = voice
    }

    /// Convert to internal TTSConfiguration
    public func toTTSConfiguration() -> TTSConfiguration? {
      guard let endpoint, let url = URL(string: endpoint), let apiKey else {
        return nil
      }
      return TTSConfiguration(
        endpointURL: url,
        apiKey: apiKey,
        model: model ?? "gpt-4o-mini-tts",
        voice: voice ?? "alloy"
      )
    }

    /// Create from internal TTSConfiguration
    public static func from(
      _ config: TTSConfiguration,
      usesDefault: Bool
    ) -> TTSEntry {
      TTSEntry(
        useDefault: usesDefault,
        endpoint: config.endpointURL.absoluteString,
        apiKey: config.apiKey,
        model: config.model,
        voice: config.voice
      )
    }
  }
}

// MARK: - Action

public extension AppConfiguration {
  struct ActionEntry: Codable, Sendable {
    public var summary: String?
    public var prompt: String
    public var providers: [String]
    public var scenes: [String]?
    public var outputType: String?

    public init(
      summary: String? = nil,
      prompt: String,
      providers: [String],
      scenes: [String]? = nil,
      outputType: String? = nil
    ) {
      self.summary = summary
      self.prompt = prompt
      self.providers = providers
      self.scenes = scenes
      self.outputType = outputType
    }

    /// Convert to internal ActionConfig
    public func toActionConfig(
      name: String,
      providerMap: [String: UUID]
    ) -> ActionConfig {
      let providerIDs = providers.compactMap { providerMap[$0] }

      let resolvedOutputType = OutputType(rawValue: outputType ?? "") ?? .plain

      let usageScenes: ActionConfig.UsageScene
      if let scenes {
        var sceneSet: ActionConfig.UsageScene = []
        for scene in scenes {
          switch scene {
          case "app":
            sceneSet.insert(.app)
          case "contextRead":
            sceneSet.insert(.contextRead)
          case "contextEdit":
            sceneSet.insert(.contextEdit)
          default:
            break
          }
        }
        usageScenes = sceneSet.isEmpty ? .all : sceneSet
      } else {
        usageScenes = .all
      }

      return ActionConfig(
        name: name,
        summary: summary ?? "",
        prompt: prompt,
        providerIDs: providerIDs,
        usageScenes: usageScenes,
        outputType: resolvedOutputType
      )
    }

    /// Create from internal ActionConfig
    public static func from(
      _ config: ActionConfig,
      providerNames: [UUID: String]
    ) -> (name: String, entry: ActionEntry) {
      let providerNameList = config.providerIDs.compactMap { providerNames[$0] }

      var scenes: [String] = []
      if config.usageScenes.contains(.app) { scenes.append("app") }
      if config.usageScenes.contains(.contextRead) { scenes.append("contextRead") }
      if config.usageScenes.contains(.contextEdit) { scenes.append("contextEdit") }

      let entry = ActionEntry(
        summary: config.summary.isEmpty ? nil : config.summary,
        prompt: config.prompt,
        providers: providerNameList,
        scenes: scenes.count == 3 ? nil : scenes,
        outputType: config.outputType == .plain ? nil : config.outputType.rawValue
      )
      return (config.name, entry)
    }
  }
}
