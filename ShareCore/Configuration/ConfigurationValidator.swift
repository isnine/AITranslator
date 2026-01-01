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

    // Build provider lookup
    let providerMap = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })

    // Validate each action's provider references
    for action in actions {
      for deployment in action.providerDeployments {
        // Check if provider exists
        guard let provider = providerMap[deployment.providerID] else {
          issues.append(
            .providerNotFound(
              providerID: deployment.providerID.uuidString,
              referencedBy: action.name
            )
          )
          continue
        }

        // Check if deployment exists in provider
        if !deployment.deployment.isEmpty
          && !provider.deployments.contains(deployment.deployment)
        {
          issues.append(
            .deploymentNotFound(
              deployment: deployment.deployment,
              provider: provider.displayName,
              referencedBy: action.name
            )
          )
        }
      }

      // Warn if action has no providers
      if action.providerDeployments.isEmpty {
        issues.append(.actionHasNoProviders(actionName: action.name))
      }
    }

    // Warn about unused providers
    let usedProviderIDs = Set(actions.flatMap { $0.providerDeployments.map(\.providerID) })
    for provider in providers where !usedProviderIDs.contains(provider.id) {
      issues.append(.unusedProvider(providerName: provider.displayName))
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

    let providerNames = Set(providers.keys)

    // Build deployment lookup: [providerName: Set<deployments>]
    var providerDeployments: [String: Set<String>] = [:]
    for (name, entry) in providers {
      var deployments = Set(entry.deployments ?? [])
      if let model = entry.model, !model.isEmpty {
        deployments.insert(model)
      }
      providerDeployments[name] = deployments
    }

    for action in actions {
      // Validate action has a name
      if action.name.isEmpty {
        issues.append(.emptyActionName)
      }

      // Validate action has a prompt
      if action.prompt.isEmpty {
        issues.append(.emptyActionPrompt(actionName: action.name))
      }

      // Validate provider references
      if action.providers.isEmpty {
        issues.append(.actionHasNoProviders(actionName: action.name))
      }

      for providerRef in action.providers {
        let (providerName, deploymentName) = parseProviderReference(providerRef)

        // Check if provider exists
        guard providerNames.contains(providerName) else {
          issues.append(
            .providerNotFound(
              providerID: providerName,
              referencedBy: action.name
            )
          )
          continue
        }

        // Check if specific deployment exists
        if let deploymentName, !deploymentName.isEmpty {
          let validDeployments = providerDeployments[providerName] ?? []
          if !validDeployments.contains(deploymentName) {
            issues.append(
              .deploymentNotFound(
                deployment: deploymentName,
                provider: providerName,
                referencedBy: action.name
              )
            )
          }
        }
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

    return issues
  }

  // MARK: - TTS Validation

  private func validateTTS(
    _ tts: AppConfiguration.TTSEntry
  ) -> [ConfigurationValidationIssue] {
    var issues: [ConfigurationValidationIssue] = []

    // Only validate if not using default
    let usesDefault = tts.useDefault ?? true
    if !usesDefault {
      if let endpoint = tts.endpoint, URL(string: endpoint) == nil {
        issues.append(.invalidTTSEndpoint(url: endpoint))
      }

      if tts.apiKey?.isEmpty ?? true {
        issues.append(.emptyTTSApiKey)
      }
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
  case unusedProvider(providerName: String)

  // Action issues
  case emptyActionName
  case emptyActionPrompt(actionName: String)
  case actionHasNoProviders(actionName: String)
  case providerNotFound(providerID: String, referencedBy: String)
  case deploymentNotFound(deployment: String, provider: String, referencedBy: String)
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
      .providerNotFound,
      .deploymentNotFound,
      .invalidOutputType:
      return .error

    // Warnings - allow saving but notify user
    case .emptyToken,
      .noDeployments,
      .unusedProvider,
      .emptyActionName,
      .emptyActionPrompt,
      .actionHasNoProviders,
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
    case .unusedProvider(let providerName):
      return "Provider '\(providerName)' is not used by any action"
    case .emptyActionName:
      return "Action has empty name"
    case .emptyActionPrompt(let actionName):
      return "Action '\(actionName)' has empty prompt"
    case .actionHasNoProviders(let actionName):
      return "Action '\(actionName)' has no providers configured"
    case .providerNotFound(let providerID, let referencedBy):
      return "Action '\(referencedBy)' references unknown provider: '\(providerID)'"
    case .deploymentNotFound(let deployment, let provider, let referencedBy):
      return "Action '\(referencedBy)' references unknown deployment '\(deployment)' in provider '\(provider)'"
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
