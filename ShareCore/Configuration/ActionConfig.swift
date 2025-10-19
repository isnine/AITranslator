//
//  ActionConfig.swift
//  ShareCore
//
//  Created by Codex on 2025/10/19.
//

import Foundation

public struct ActionConfig: Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var prompt: String
    public var providerIDs: [UUID]

    public init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        providerIDs: [UUID]
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.providerIDs = providerIDs
    }
}
