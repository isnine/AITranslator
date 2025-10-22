//
//  ActionConfig.swift
//  ShareCore
//
//  Created by Codex on 2025/10/19.
//

import Foundation

public struct ActionConfig: Identifiable, Hashable {
    public struct UsageScene: OptionSet, Hashable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let app = UsageScene(rawValue: 1 << 0)
        public static let contextRead = UsageScene(rawValue: 1 << 1)
        public static let contextEdit = UsageScene(rawValue: 1 << 2)

        public static let all: UsageScene = [.app, .contextRead, .contextEdit]
    }

    public let id: UUID
    public var name: String
    public var prompt: String
    public var providerIDs: [UUID]
    public var usageScenes: UsageScene

    public init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        providerIDs: [UUID],
        usageScenes: UsageScene
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.providerIDs = providerIDs
        self.usageScenes = usageScenes
    }
}
