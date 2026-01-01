//
//  ConfigurationValidator.swift
//  ShareCore
//
//  Created by AI Assistant on 2026/01/01.
//

import Foundation

/// Validates configuration integrity and compatibility
public struct ConfigurationValidator: Sendable {
  public static let shared = ConfigurationValidator()

  /// Current supported major version
  public static let currentMajorVersion = 1

  /// Supported major version range (inclusive)
  public static let supportedVersionRange = 1...1

  private init() {}

  // MARK: - Full Configuration Validation

  /// Validate an AppConfiguration and return all issues found
  public func validate(_ config: AppConfiguration) -> ConfigurationValidationResult {
    var issues: [ConfigurationValidationIssue] = []

    // 1. Version validation
    issues.append(contentsOf: validateVersion(config.version))

    // 2. Provider validation
    issues.append(contentsOf: validateProviders(config.providers))

    // 3. Action validation (including provider references)
    issues.append(contentsOf: validateActions(config.actions, providers: config.providers))

    // 4. TTS validation
    if let tts = config.tts {
      issues.append(contentsOf: validateTTS(tts))
    }

    return ConfigurationValidationResult(issues: issues)
  }

  /// Validate in-memory configuration (actions and providers)
  @MainActor
  public func validateInMemory(
    actions: [ActionConfig],
    providers: [ProviderConfig]
  ) -> ConfigurationValidationResult {
    var issues: [ConfigurationValidationIssue] = []

    // Validate each action
    for action in actions {
      // Validate action has a name
      if action.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(.emptyActionName)
      }

      // Validate action has a prompt
      if action.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(.emptyActionPrompt(actionName: action.name))
      }
    }

    // Check for duplicate action names
    var seenNames: Set<String> = []
    for action in actions {
      if seenNames.contains(action.name) {
        issues.append(.duplicateActionName(actionName: action.name))
      }
      seenNames.insert(action.name)
    }

    // Validate providers have enabled deployments
    for provider in providers {
      if provider.enabledDeployments.isEmpty {
        issues.append(.noEnabledDeployments(providerName: provider.displayName))
      }
    }

    // Warn if no providers configured at all
    if providers.isEmpty {
      issues.append(.noProvidersConfigured)
    }

    return ConfigurationValidationResult(issues: issues)
  }

  // MARK: - Version Validation

  private func validateVersion(_ version: String) -> [ConfigurationValidationIssue] {
    var issues: [ConfigurationValidationIssue] = []

    let components = version.split(separator: ".").compactMap { Int($0) }

    guard components.count >= 2 else {
      issues.append(.invalidVersionFormat(version: version))
      return issues
    }

    let major = components[0]

    if !Self.supportedVersionRange.contains(major) {
      issues.append(
        .unsupportedVersion(
          version: version,
          supportedRange: "\(Self.supportedVersionRange.lowerBound).x.x - \(Self.supportedVersionRange.upperBound).x.x"
        )
      )
    }

    return issues
  }

  // MARK: - Provider Validation

  private func validateProviders(
    _ providers: [String: AppConfiguration.ProviderEntry]
  ) -> [ConfigurationValidationIssue] {
    var issues: [ConfigurationValidationIssue] = []

    for (name, entry) in providers {
      // Validate category
      if ProviderCategory(rawValue: entry.category) == nil
        && ProviderCategory.allCases.first(where: { $0.displayName == entry.category }) == nil
      {
        issues.append(.invalidProviderCategory(provider: name, category: entry.category))
      }

      // Validate endpoint URL
      if let baseEndpoint = entry.baseEndpoint {
        if URL(string: baseEndpoint) == nil {
          issues.append(.invalidEndpointURL(provider: name, url: baseEndpoint))
        }
      } else if let endpoint = entry.endpoint {
        if URL(string: endpoint) == nil {
          issues.append(.invalidEndpointURL(provider: name, url: endpoint))
        }
      } else {
        issues.append(.missingEndpoint(provider: name))
      }

      // Validate token is not empty
      if entry.token.isEmpty {
        issues.append(.emptyToken(provider: name))
      }

      // Warn if no deployments
      if entry.deployments?.isEmpty ?? true, entry.model?.isEmpty ?? true {
        issues.append(.noDeployments(provider: name))
      }
    }

    return issues
  }

  // MARK: - Action Validation

  private func validateActions(
    _ actions: [AppConfiguration.ActionEntry],
    providers: [String: AppConfiguration.ProviderEntry]
  ) -> [ConfigurationValidationIssue] {
    var issues: [ConfigurationValidationIssue] = []

    for action in actions {
      // Validate action has a name
      if action.name.isEmpty {
        issues.append(.emptyActionName)
      }

      // Validate action has a prompt
      if action.prompt.isEmpty {
        issues.append(.emptyActionPrompt(actionName: action.name))
      }

      // Validate output type
      if let outputType = action.outputType,
        OutputType(rawValue: outputType) == nil
      {
        issues.append(.invalidOutputType(actionName: action.name, outputType: outputType))
      }
    }

    // Check for duplicate action names
    var seenNames: Set<String> = []
    for action in actions {
      if seenNames.contains(action.name) {
        issues.append(.duplicateActionName(actionName: action.name))
      }
      seenNames.insert(action.name)
    }

    // Check if any providers have enabled deployments
    let hasEnabledDeployments = providers.values.contains { entry in
      let enabled = entry.enabledDeployments ?? entry.deployments ?? []
      return !enabled.isEmpty
    }
    if !hasEnabledDeployments && !providers.isEmpty {
      issues.append(.noEnabledDeployments(providerName: ""))
    }

    return issues
  }

  // MARK: - TTS Validation

  private func validateTTS(
    _ tts: AppConfiguration.TTSEntry
  ) -> [ConfigurationValidationIssue] {
    var issues: [ConfigurationValidationIssue] = []

    // Validate endpoint URL format if provided
    if let endpoint = tts.endpoint, !endpoint.isEmpty, URL(string: endpoint) == nil {
      issues.append(.invalidTTSEndpoint(url: endpoint))
    }

    // Warn if API key is empty (TTS won't work without it)
    if tts.apiKey?.isEmpty ?? true {
      issues.append(.emptyTTSApiKey)
    }

    return issues
  }

  // MARK: - Helpers

  /// Parse "ProviderName:deployment" format
  private func parseProviderReference(_ ref: String) -> (provider: String, deployment: String?) {
    if let colonIndex = ref.firstIndex(of: ":") {
      let provider = String(ref[..<colonIndex])
      let deployment = String(ref[ref.index(after: colonIndex)...])
      return (provider, deployment)
    }
    return (ref, nil)
  }
}

// MARK: - Validation Result

public struct ConfigurationValidationResult: Sendable {
  public let issues: [ConfigurationValidationIssue]

  public var isValid: Bool {
    !hasErrors
  }

  public var hasErrors: Bool {
    issues.contains { $0.severity == .error }
  }

  public var hasWarnings: Bool {
    issues.contains { $0.severity == .warning }
  }

  public var errors: [ConfigurationValidationIssue] {
    issues.filter { $0.severity == .error }
  }

  public var warnings: [ConfigurationValidationIssue] {
    issues.filter { $0.severity == .warning }
  }

  public init(issues: [ConfigurationValidationIssue]) {
    self.issues = issues
  }

  /// Empty result with no issues
  public static let valid = ConfigurationValidationResult(issues: [])
}

// MARK: - Validation Issue

public enum ConfigurationValidationIssue: Sendable, Equatable {
  // Version issues
  case invalidVersionFormat(version: String)
  case unsupportedVersion(version: String, supportedRange: String)

  // Provider issues
  case invalidProviderCategory(provider: String, category: String)
  case invalidEndpointURL(provider: String, url: String)
  case missingEndpoint(provider: String)
  case emptyToken(provider: String)
  case noDeployments(provider: String)
  case noEnabledDeployments(providerName: String)
  case noProvidersConfigured

  // Action issues
  case emptyActionName
  case emptyActionPrompt(actionName: String)
  case invalidOutputType(actionName: String, outputType: String)
  case duplicateActionName(actionName: String)

  // TTS issues
  case invalidTTSEndpoint(url: String)
  case emptyTTSApiKey

  /// Severity level of the issue
  public var severity: ValidationSeverity {
    switch self {
    // Errors - prevent saving or loading
    case .invalidVersionFormat,
      .unsupportedVersion,
      .invalidProviderCategory,
      .invalidEndpointURL,
      .missingEndpoint,
      .invalidOutputType:
      return .error

    // Warnings - allow saving but notify user
    case .emptyToken,
      .noDeployments,
      .noEnabledDeployments,
      .noProvidersConfigured,
      .emptyActionName,
      .emptyActionPrompt,
      .duplicateActionName,
      .invalidTTSEndpoint,
      .emptyTTSApiKey:
      return .warning
    }
  }

  /// Human-readable description
  public var message: String {
    switch self {
    case .invalidVersionFormat(let version):
      return "Invalid version format: '\(version)'. Expected format: X.Y.Z"
    case .unsupportedVersion(let version, let supportedRange):
      return "Version '\(version)' is not supported. Supported range: \(supportedRange)"
    case .invalidProviderCategory(let provider, let category):
      return "Provider '\(provider)' has invalid category: '\(category)'"
    case .invalidEndpointURL(let provider, let url):
      return "Provider '\(provider)' has invalid endpoint URL: '\(url)'"
    case .missingEndpoint(let provider):
      return "Provider '\(provider)' is missing endpoint URL"
    case .emptyToken(let provider):
      return "Provider '\(provider)' has empty API token"
    case .noDeployments(let provider):
      return "Provider '\(provider)' has no deployments configured"
    case .noEnabledDeployments(let providerName):
      if providerName.isEmpty {
        return "No enabled deployments found across all providers"
      }
      return "Provider '\(providerName)' has no enabled deployments"
    case .noProvidersConfigured:
      return "No providers configured"
    case .emptyActionName:
      return "Action has empty name"
    case .emptyActionPrompt(let actionName):
      return "Action '\(actionName)' has empty prompt"
    case .invalidOutputType(let actionName, let outputType):
      return "Action '\(actionName)' has invalid output type: '\(outputType)'"
    case .duplicateActionName(let actionName):
      return "Duplicate action name: '\(actionName)'"
    case .invalidTTSEndpoint(let url):
      return "TTS has invalid endpoint URL: '\(url)'"
    case .emptyTTSApiKey:
      return "TTS API key is empty"
    }
  }
}

// MARK: - Severity

public enum ValidationSeverity: String, Sendable {
  case error
  case warning
}
