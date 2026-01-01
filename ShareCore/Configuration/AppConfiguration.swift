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
  public var actions: [ActionEntry]

  public init(
    version: String = "1.0.0",
    preferences: PreferencesConfig? = nil,
    providers: [String: ProviderEntry] = [:],
    tts: TTSEntry? = nil,
    actions: [ActionEntry] = []
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
    // New format fields
    public var baseEndpoint: String?
    public var apiVersion: String?
    public var deployments: [String]?
    public var enabledDeployments: [String]?
    // Legacy format fields (for backward compatibility)
    public var model: String?
    public var endpoint: String?
    public var authHeader: String?
    public var token: String

    public init(
      category: String,
      baseEndpoint: String? = nil,
      apiVersion: String? = nil,
      deployments: [String]? = nil,
      enabledDeployments: [String]? = nil,
      model: String? = nil,
      endpoint: String? = nil,
      authHeader: String? = nil,
      token: String
    ) {
      self.category = category
      self.baseEndpoint = baseEndpoint
      self.apiVersion = apiVersion
      self.deployments = deployments
      self.enabledDeployments = enabledDeployments
      self.model = model
      self.endpoint = endpoint
      self.authHeader = authHeader
      self.token = token
    }

    /// Convert to internal ProviderConfig
    public func toProviderConfig(name: String) -> ProviderConfig? {
      guard let providerCategory = ProviderCategory(rawValue: category)
        ?? ProviderCategory.allCases.first(where: { $0.displayName == category }) else {
        return nil
      }

      let resolvedAuthHeader: String
      if let authHeader, !authHeader.isEmpty {
        resolvedAuthHeader = authHeader
      } else {
        resolvedAuthHeader = providerCategory == .azureOpenAI ? "api-key" : "Authorization"
      }

      // New format: baseEndpoint + apiVersion + deployments
      if let baseEndpointStr = baseEndpoint, let baseURL = URL(string: baseEndpointStr) {
        let version = apiVersion ?? "2024-02-15-preview"
        let deploymentList = deployments ?? []
        let enabledSet = enabledDeployments.map { Set($0) } ?? Set(deploymentList)
        
        return ProviderConfig(
          displayName: name,
          baseEndpoint: baseURL,
          apiVersion: version,
          token: token,
          authHeaderName: resolvedAuthHeader,
          category: providerCategory,
          deployments: deploymentList,
          enabledDeployments: enabledSet
        )
      }
      
      // Legacy format: full endpoint URL
      guard let endpointStr = endpoint, let url = URL(string: endpointStr) else {
        return nil
      }

      // Use legacy initializer which parses the full URL
      return ProviderConfig(
        displayName: name,
        apiURL: url,
        token: token,
        authHeaderName: resolvedAuthHeader,
        category: providerCategory,
        modelName: model
      )
    }

    /// Create from internal ProviderConfig (always uses new format)
    public static func from(_ config: ProviderConfig) -> (name: String, entry: ProviderEntry) {
      let entry = ProviderEntry(
        category: config.category.rawValue,
        baseEndpoint: config.baseEndpoint.absoluteString,
        apiVersion: config.apiVersion,
        deployments: config.deployments,
        enabledDeployments: Array(config.enabledDeployments),
        model: nil,
        endpoint: nil,
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
    public var endpoint: String?
    public var apiKey: String?
    public var model: String?
    public var voice: String?

    public init(
      endpoint: String? = nil,
      apiKey: String? = nil,
      model: String? = nil,
      voice: String? = nil
    ) {
      self.endpoint = endpoint
      self.apiKey = apiKey
      self.model = model
      self.voice = voice
    }

    /// Convert to internal TTSConfiguration
    public func toTTSConfiguration() -> TTSConfiguration {
      let endpointURL = endpoint.flatMap { URL(string: $0) } ?? URL(string: "https://")!
      return TTSConfiguration(
        endpointURL: endpointURL,
        apiKey: apiKey ?? "",
        model: model ?? "",
        voice: voice ?? ""
      )
    }

    /// Create from internal TTSConfiguration
    public static func from(_ config: TTSConfiguration) -> TTSEntry {
      TTSEntry(
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
    public var name: String
    public var summary: String?
    public var prompt: String
    public var scenes: [String]?
    public var outputType: String?

    public init(
      name: String,
      summary: String? = nil,
      prompt: String,
      scenes: [String]? = nil,
      outputType: String? = nil
    ) {
      self.name = name
      self.summary = summary
      self.prompt = prompt
      self.scenes = scenes
      self.outputType = outputType
    }

    /// Convert to internal ActionConfig
    public func toActionConfig() -> ActionConfig {
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
        usageScenes: usageScenes,
        outputType: resolvedOutputType
      )
    }

    /// Create from internal ActionConfig
    public static func from(_ config: ActionConfig) -> ActionEntry {
      var scenes: [String] = []
      if config.usageScenes.contains(.app) { scenes.append("app") }
      if config.usageScenes.contains(.contextRead) { scenes.append("contextRead") }
      if config.usageScenes.contains(.contextEdit) { scenes.append("contextEdit") }

      return ActionEntry(
        name: config.name,
        summary: config.summary.isEmpty ? nil : config.summary,
        prompt: config.prompt,
        scenes: scenes.count == 3 ? nil : scenes,
        outputType: config.outputType == .plain ? nil : config.outputType.rawValue
      )
    }
  }
}
