//
//  BuildEnvironment.swift
//  ShareCore
//
//  Created by AITranslator on 2025/01/31.
//

import Foundation

/// Configuration loaded from xcconfig/Info.plist/environment variables
///
/// Priority order (highest to lowest):
/// 1. Environment variables (for CI/CD)
/// 2. Info.plist values (injected from xcconfig at build time)
/// 3. Secrets.plist (for local development fallback)
/// 4. Default values
public enum BuildEnvironment {
    // MARK: - Environment Variable Keys

    private enum EnvKeys {
        static let cloudEndpoint = "AITRANSLATOR_CLOUD_ENDPOINT"
        static let cloudSecret = "AITRANSLATOR_CLOUD_SECRET"
    }

    // MARK: - Info.plist Keys

    private enum InfoPlistKeys {
        static let cloudEndpoint = "AITranslatorCloudEndpoint"
        static let cloudSecret = "AITranslatorCloudSecret"
    }

    // MARK: - Default Values

    private enum Defaults {
        #if DEBUG
            static let cloudEndpoint = "https://aitranslator-dev.xiaozwan.workers.dev"
        #else
            static let cloudEndpoint = "https://translator-api.zanderwang.com"
        #endif
    }

    // MARK: - Public Properties

    /// Cloud service API endpoint URL
    public static var cloudEndpoint: URL {
        let urlString = loadValue(
            envKey: EnvKeys.cloudEndpoint,
            plistKey: InfoPlistKeys.cloudEndpoint,
            secretsPlistKey: nil
        ) ?? Defaults.cloudEndpoint

        return URL(string: urlString) ?? URL(string: Defaults.cloudEndpoint)!
    }

    /// Cloud service HMAC signing secret
    public static var cloudSecret: String {
        loadValue(
            envKey: EnvKeys.cloudSecret,
            plistKey: InfoPlistKeys.cloudSecret,
            secretsPlistKey: "BuiltInCloudSecret"
        ) ?? ""
    }

    /// Whether cloud service credentials are configured
    public static var isCloudConfigured: Bool {
        !cloudSecret.isEmpty
    }

    /// API version for the cloud service
    public static let apiVersion = "2025-01-01-preview"

    // MARK: - Validation

    /// Validates that required configuration is present
    /// - Returns: Array of missing configuration descriptions
    public static func validateConfiguration() -> [String] {
        var missing: [String] = []

        if cloudSecret.isEmpty {
            missing.append("Cloud Secret (AITRANSLATOR_CLOUD_SECRET)")
        }

        return missing
    }

    /// Debug description of current configuration (secrets redacted)
    public static var debugDescription: String {
        """
        BuildEnvironment:
          - Cloud Endpoint: \(cloudEndpoint.absoluteString)
          - Cloud Secret: \(cloudSecret.isEmpty ? "(not set)" : "(set, \(cloudSecret.count) chars)")
          - Is Configured: \(isCloudConfigured)
        """
    }

    // MARK: - Private Loading Logic

    private static func loadValue(
        envKey: String,
        plistKey: String,
        secretsPlistKey: String?
    ) -> String? {
        // 1. Environment variable (highest priority - for CI/CD)
        if let envValue = ProcessInfo.processInfo.environment[envKey],
           !envValue.isEmpty
        {
            return envValue
        }

        // 2. Info.plist (injected from xcconfig at build time)
        if let plistValue = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String,
           !plistValue.isEmpty,
           !plistValue.hasPrefix("$(")
        { // Skip unresolved xcconfig variables
            return plistValue
        }

        // 3. Secrets.plist in main bundle (for local development)
        if let secretsKey = secretsPlistKey,
           let bundlePath = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let secrets = NSDictionary(contentsOfFile: bundlePath),
           let value = secrets[secretsKey] as? String,
           !value.isEmpty
        {
            return value
        }

        // 4. Secrets.plist in App Group container
        if let secretsKey = secretsPlistKey,
           let containerURL = FileManager.default.containerURL(
               forSecurityApplicationGroupIdentifier: AppPreferences.appGroupSuiteName
           )
        {
            let appGroupPath = containerURL.appendingPathComponent("Secrets.plist").path
            if let secrets = NSDictionary(contentsOfFile: appGroupPath),
               let value = secrets[secretsKey] as? String,
               !value.isEmpty
            {
                return value
            }
        }

        return nil
    }
}
