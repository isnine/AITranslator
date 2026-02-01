//
//  SecretsConfiguration.swift
//  ShareCore
//
//  Created by AITranslator on 2025/01/30.
//

import Foundation

/// Manages loading of secrets from environment variables or local configuration files.
/// Secrets are loaded in order of priority:
/// 1. Environment variables (for CI/CD and development)
/// 2. Secrets.plist in the app bundle (for local development)
/// 3. App Group container Secrets.plist (for shared access)
///
/// **IMPORTANT:** Never commit real secrets to the repository.
/// See README.md for configuration instructions.
public enum SecretsConfiguration {
    // MARK: - Environment Variable Keys

    private enum EnvKeys {
        static let builtInCloudSecret = "AITRANSLATOR_BUILTIN_CLOUD_SECRET"
        static let azureApiKey = "AITRANSLATOR_AZURE_API_KEY"
        static let azureEndpoint = "AITRANSLATOR_AZURE_ENDPOINT"
    }

    // MARK: - Plist Keys

    private enum PlistKeys {
        static let builtInCloudSecret = "BuiltInCloudSecret"
        static let azureApiKey = "AzureApiKey"
        static let azureEndpoint = "AzureEndpoint"
    }

    // MARK: - Loaded Secrets

    /// HMAC secret for Built-in Cloud service authentication
    public static var builtInCloudSecret: String {
        loadSecret(envKey: EnvKeys.builtInCloudSecret, plistKey: PlistKeys.builtInCloudSecret) ?? ""
    }

    /// Azure OpenAI API Key (optional, for direct Azure access)
    public static var azureApiKey: String? {
        loadSecret(envKey: EnvKeys.azureApiKey, plistKey: PlistKeys.azureApiKey)
    }

    /// Azure OpenAI Endpoint (optional, for direct Azure access)
    public static var azureEndpoint: String? {
        loadSecret(envKey: EnvKeys.azureEndpoint, plistKey: PlistKeys.azureEndpoint)
    }

    /// Whether the built-in cloud secret is configured
    public static var isBuiltInCloudConfigured: Bool {
        !builtInCloudSecret.isEmpty
    }

    // MARK: - Private Loading Logic

    private static func loadSecret(envKey: String, plistKey: String) -> String? {
        // 1. Try environment variable first
        if let envValue = ProcessInfo.processInfo.environment[envKey], !envValue.isEmpty {
            return envValue
        }

        // 2. Try Secrets.plist in main bundle
        if let bundlePath = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let secrets = NSDictionary(contentsOfFile: bundlePath),
           let value = secrets[plistKey] as? String,
           !value.isEmpty
        {
            return value
        }

        // 3. Try Secrets.plist in App Group container
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppPreferences.appGroupSuiteName
        ) {
            let appGroupPath = containerURL.appendingPathComponent("Secrets.plist").path
            if let secrets = NSDictionary(contentsOfFile: appGroupPath),
               let value = secrets[plistKey] as? String,
               !value.isEmpty
            {
                return value
            }
        }

        return nil
    }

    // MARK: - Validation

    /// Validates that required secrets are configured
    /// - Returns: Array of missing secret descriptions
    public static func validateRequiredSecrets() -> [String] {
        var missing: [String] = []

        if builtInCloudSecret.isEmpty {
            missing.append("Built-in Cloud Secret (AITRANSLATOR_BUILTIN_CLOUD_SECRET or Secrets.plist)")
        }

        return missing
    }
}
