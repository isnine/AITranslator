//
//  ProviderConfig.swift
//  ShareCore
//
//  Created by Codex on 2025/10/19.
//

import Foundation

public struct ProviderConfig: Identifiable, Hashable, Codable {
    public let id: UUID
    public var displayName: String
    /// Base endpoint URL (e.g., https://xxx.openai.azure.com/openai/deployments)
    public var baseEndpoint: URL
    /// API version parameter (e.g., 2025-01-01-preview)
    public var apiVersion: String
    public var token: String
    public var authHeaderName: String
    public var category: ProviderCategory
    /// All available deployment names
    public var deployments: [String]
    /// Deployments that are enabled for use (subset of deployments)
    public var enabledDeployments: Set<String>

    // MARK: - Built-in Cloud Constants

    /// CloudFlare worker endpoint for Built-in Cloud provider
    public static let builtInCloudEndpoint = URL(string: "https://translator-api.zanderwang.com")!

    /// Available models for Built-in Cloud provider
    public static let builtInCloudAvailableModels = ["model-router", "gpt-4.1-nano"]

    /// Default model for Built-in Cloud provider
    public static let builtInCloudDefaultModel = "model-router"

    /// Shared secret for HMAC signing (used with Built-in Cloud provider)
    public static let builtInCloudSecret = "REDACTED_HMAC_SECRET"

    /// Creates a Built-in Cloud provider config with specified models
    public static func builtInCloudProvider(enabledModels: Set<String>? = nil) -> ProviderConfig {
        let enabled = enabledModels ?? Set(builtInCloudAvailableModels)
        return ProviderConfig(
            displayName: "Built-in Cloud",
            baseEndpoint: builtInCloudEndpoint,
            apiVersion: "2025-01-01-preview",
            token: "",
            authHeaderName: "api-key",
            category: .builtInCloud,
            deployments: builtInCloudAvailableModels,
            enabledDeployments: enabled
        )
    }

    /// Computed property to get full API URL for a specific deployment
    public func apiURL(for deployment: String) -> URL {
        let path = baseEndpoint.appendingPathComponent(deployment)
            .appendingPathComponent("chat/completions")
        var components = URLComponents(url: path, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "api-version", value: apiVersion)]
        return components.url!
    }

    /// Default API URL using first deployment (for backward compatibility)
    public var apiURL: URL {
        guard let firstDeployment = deployments.first else {
            return baseEndpoint
        }
        return apiURL(for: firstDeployment)
    }

    /// Model name is now derived from deployments
    public var modelName: String {
        deployments.first ?? ""
    }

    public init(
        id: UUID = UUID(),
        displayName: String,
        baseEndpoint: URL,
        apiVersion: String = "2024-02-15-preview",
        token: String,
        authHeaderName: String = "api-key",
        category: ProviderCategory = .custom,
        deployments: [String] = [],
        enabledDeployments: Set<String>? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.baseEndpoint = baseEndpoint
        self.apiVersion = apiVersion
        self.token = token
        self.authHeaderName = authHeaderName
        self.category = category
        self.deployments = deployments
        // If enabledDeployments not specified, enable all deployments by default
        self.enabledDeployments = enabledDeployments ?? Set(deployments)
    }

    /// Legacy initializer for backward compatibility with old JSON format
    public init(
        id: UUID = UUID(),
        displayName: String,
        apiURL: URL,
        token: String,
        authHeaderName: String = "api-key",
        category: ProviderCategory = .custom,
        modelName: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.token = token
        self.authHeaderName = authHeaderName
        self.category = category

        // Parse legacy apiURL to extract baseEndpoint, apiVersion, and deployment
        if let components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false) {
            // Extract api-version from query
            let version = components.queryItems?.first(where: { $0.name == "api-version" })?.value ?? "2024-02-15-preview"
            self.apiVersion = version

            // Extract deployment from path (format: .../deployments/{deployment}/chat/completions)
            var pathComponents = apiURL.pathComponents
            if let chatIndex = pathComponents.firstIndex(of: "chat"),
               chatIndex > 0,
               pathComponents[chatIndex - 1] != "deployments" {
                let deploymentName = pathComponents[chatIndex - 1]
                // Remove /chat/completions from path to get base endpoint
                pathComponents = Array(pathComponents.dropLast(2)) // Remove "chat" and "completions"
                pathComponents = Array(pathComponents.dropLast()) // Remove deployment name
                var baseComponents = components
                baseComponents.queryItems = nil
                baseComponents.path = pathComponents.joined(separator: "/")
                self.baseEndpoint = baseComponents.url ?? apiURL
                self.deployments = [deploymentName]
                self.enabledDeployments = Set([deploymentName])
            } else {
                // Fallback: use original URL as base
                var baseComponents = components
                baseComponents.queryItems = nil
                self.baseEndpoint = baseComponents.url ?? apiURL
                self.deployments = modelName.map { [$0] } ?? []
                self.enabledDeployments = Set(self.deployments)
            }
        } else {
            self.baseEndpoint = apiURL
            self.apiVersion = "2024-02-15-preview"
            self.deployments = modelName.map { [$0] } ?? []
            self.enabledDeployments = Set(self.deployments)
        }
    }
}
