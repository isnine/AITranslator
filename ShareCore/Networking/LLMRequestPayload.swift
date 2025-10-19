//
//  LLMRequestPayload.swift
//  ShareCore
//
//  Created by Codex on 2025/10/19.
//

import Foundation

public struct LLMRequestPayload: Codable {
    public struct Message: Codable {
        public let role: String
        public let content: String

        public init(role: String, content: String) {
            self.role = role
            self.content = content
        }
    }

    public let messages: [Message]
    public let stream: Bool?

    public init(messages: [Message], stream: Bool? = nil) {
        self.messages = messages
        self.stream = stream
    }
}
