//
//  LocalProviderService.swift
//  ShareCore
//
//  Created by Codex on 2025/01/05.
//

import Foundation
import os

private let localProviderLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TLingo", category: "LocalProvider")

/// Unified service for managing local on-device providers
public final class LocalProviderService: Sendable {
    public static let shared = LocalProviderService()
    
    /// Available local deployment types
    public enum LocalDeployment: String, CaseIterable, Sendable {
        case appleTranslation = "Apple Translation"
        case appleFoundation = "Apple Foundation"
        
        public var displayName: String { rawValue }
        
        /// Whether this deployment is available on the current device
        public var isAvailable: Bool {
            let available: Bool
            switch self {
            case .appleTranslation:
                available = AppleTranslationService.shared.isAvailable
            case .appleFoundation:
                available = AppleFoundationService.shared.isAvailable
            }
            localProviderLogger.info("Checking availability for \(self.rawValue): \(available)")
            return available
        }
        
        /// Status message for this deployment
        public var statusMessage: String {
            switch self {
            case .appleTranslation:
                return AppleTranslationService.shared.availabilityStatus
            case .appleFoundation:
                return AppleFoundationService.shared.availabilityStatus
            }
        }
        
        /// Whether this deployment supports the given action
        public func supportsAction(_ action: ActionConfig) -> Bool {
            let supported: Bool
            switch self {
            case .appleTranslation:
                // Apple Translation only supports translation actions
                supported = isTranslationAction(action)
            case .appleFoundation:
                // Apple Foundation supports all actions
                supported = true
            }
            localProviderLogger.info("\(self.rawValue) supports action '\(action.name)': \(supported)")
            return supported
        }
        
        /// Check if the action is a translation action
        private func isTranslationAction(_ action: ActionConfig) -> Bool {
            // Check by output type or action name pattern
            let name = action.name.lowercased()
            return name.contains("translat") || action.outputType == .sentencePairs
        }
    }
    
    private init() {}
    
    // MARK: - Availability
    
    /// Get all available local deployments
    public var availableDeployments: [LocalDeployment] {
        LocalDeployment.allCases.filter { $0.isAvailable }
    }
    
    /// Get all local deployments with their availability status
    public var allDeploymentsWithStatus: [(deployment: LocalDeployment, isAvailable: Bool, status: String)] {
        LocalDeployment.allCases.map { deployment in
            (deployment: deployment, isAvailable: deployment.isAvailable, status: deployment.statusMessage)
        }
    }
    
    // MARK: - Provider Config Factory
    
    /// Create a local provider config
    public static func createLocalProvider() -> ProviderConfig {
        let availableDeployments = LocalDeployment.allCases
            .filter { $0.isAvailable }
            .map { $0.rawValue }
        
        return ProviderConfig(
            displayName: NSLocalizedString("Local", comment: "Local provider name"),
            baseEndpoint: URL(string: "local://device")!,
            apiVersion: "1.0",
            token: "",
            authHeaderName: "",
            category: .local,
            deployments: LocalDeployment.allCases.map { $0.rawValue },
            enabledDeployments: Set(availableDeployments)
        )
    }
    
    /// Check if a deployment is available
    public func isDeploymentAvailable(_ deploymentName: String) -> Bool {
        guard let deployment = LocalDeployment(rawValue: deploymentName) else {
            localProviderLogger.warning("Unknown deployment: \(deploymentName)")
            return false
        }
        let available = deployment.isAvailable
        localProviderLogger.info("isDeploymentAvailable('\(deploymentName)'): \(available)")
        return available
    }
    
    /// Get deployment status message
    public func deploymentStatus(_ deploymentName: String) -> String {
        guard let deployment = LocalDeployment(rawValue: deploymentName) else {
            return NSLocalizedString("Unknown deployment", comment: "Unknown local deployment")
        }
        return deployment.statusMessage
    }
}

// MARK: - Apple Foundation Service (Mock Implementation)

/// Mock service for Apple Foundation Models (to be implemented when available)
public final class AppleFoundationService: Sendable {
    public static let shared = AppleFoundationService()
    
    /// Deployment name for Apple Foundation
    public static let deploymentName = "Apple Foundation"
    
    private init() {}
    
    // MARK: - Availability
    
    /// Check if Apple Foundation Models is available on this device
    public var isAvailable: Bool {
        // TODO: Implement actual availability check when Foundation Models is available
        // For now, always return false as it's not yet released
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            // Check if Apple Intelligence is enabled
            // return SystemLanguageModel.default.isAvailable
            return false
        }
        #endif
        return false
    }
    
    /// Returns the availability status message
    public var availabilityStatus: String {
        if isAvailable {
            return NSLocalizedString("Ready to use", comment: "Apple Foundation available status")
        } else {
            return NSLocalizedString("Requires Apple Intelligence", comment: "Apple Foundation unavailable status")
        }
    }
    
    // MARK: - Mock Generation
    
    /// Generate text using Apple Foundation Models (Mock)
    /// - Parameters:
    ///   - text: The input text
    ///   - systemPrompt: The system prompt/instructions
    /// - Returns: Generated text
    public func generate(
        text: String,
        systemPrompt: String
    ) async throws -> String {
        // Mock implementation - simulate delay
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        return "[Mock] Apple Foundation response for: \(text.prefix(50))..."
    }
    
    /// Generate text with streaming (Mock)
    /// - Parameters:
    ///   - text: The input text
    ///   - systemPrompt: The system prompt/instructions
    ///   - partialHandler: Handler for partial results
    /// - Returns: Final generated text
    public func generateStreaming(
        text: String,
        systemPrompt: String,
        partialHandler: @MainActor @Sendable (String) -> Void
    ) async throws -> String {
        // Mock implementation - simulate streaming
        let mockResponse = "[Mock] This is a simulated response from Apple Foundation Models for your input."
        let words = mockResponse.split(separator: " ")
        
        var accumulated = ""
        for word in words {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second per word
            accumulated += (accumulated.isEmpty ? "" : " ") + word
            await partialHandler(accumulated)
        }
        
        return accumulated
    }
}
