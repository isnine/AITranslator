//
//  AppConfiguration.swift
//  ShareCore
//
//  Created by AI Assistant on 2025/12/31.
//

import Foundation

/// Root configuration structure for import/export
/// Now only contains actions - preferences and TTS are managed by UserDefaults
public struct AppConfiguration: Codable, Sendable {
    public var version: String
    public var actions: [ActionEntry]

    /// Single source of truth for the current configuration version.
    public static let currentVersion = "1.4.0"

    public init(
        version: String = AppConfiguration.currentVersion,
        actions: [ActionEntry] = []
    ) {
        self.version = version
        self.actions = actions
    }
}

// MARK: - Action

public extension AppConfiguration {
    struct ActionEntry: Codable, Sendable {
        public var name: String
        public var prompt: String
        public var scenes: [String]?
        public var outputType: String?
        public var category: String?

        public init(
            name: String,
            prompt: String,
            scenes: [String]? = nil,
            outputType: String? = nil,
            category: String? = nil
        ) {
            self.name = name
            self.prompt = prompt
            self.scenes = scenes
            self.outputType = outputType
            self.category = category
        }

        /// Convert to internal ActionConfig
        public func toActionConfig() -> ActionConfig {
            let resolvedOutputType = OutputType(rawValue: outputType ?? "") ?? .plain
            let resolvedCategory = ActionConfig.ActionCategory(rawValue: category ?? "") ?? .general

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
                prompt: prompt,
                usageScenes: usageScenes,
                outputType: resolvedOutputType,
                category: resolvedCategory
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
                prompt: config.prompt,
                scenes: scenes.count == 3 ? nil : scenes,
                outputType: config.outputType == .plain ? nil : config.outputType.rawValue,
                category: config.category == .general ? nil : config.category.rawValue
            )
        }
    }
}
