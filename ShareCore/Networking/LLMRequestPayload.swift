//
//  LLMRequestPayload.swift
//  ShareCore
//
//  Created by Codex on 2025/10/19.
//

import Foundation

public struct LLMRequestPayload: Encodable {
    public struct Message: Encodable {
        public let role: String
        /// For text-only messages, this is a plain string.
        /// For multimodal messages (text + images), this is an array of content parts.
        private let contentValue: ContentValue

        enum ContentValue {
            case text(String)
            case parts([ContentPart])
        }

        /// Convenience accessor — returns the text content (first text part for multimodal).
        public var textContent: String {
            switch contentValue {
            case .text(let str):
                return str
            case .parts(let parts):
                return parts.compactMap { part in
                    if case .text(let t) = part { return t }
                    return nil
                }.joined()
            }
        }

        // MARK: - Content Parts

        public enum ContentPart {
            case text(String)
            case imageURL(String) // base64 data URL
        }

        // MARK: - Initializers

        /// Text-only message (backward compatible)
        public init(role: String, content: String) {
            self.role = role
            self.contentValue = .text(content)
        }

        /// Multimodal message with text + images
        public init(role: String, text: String, imageDataURLs: [String]) {
            self.role = role
            if imageDataURLs.isEmpty {
                self.contentValue = .text(text)
            } else {
                var parts: [ContentPart] = [.text(text)]
                for url in imageDataURLs {
                    parts.append(.imageURL(url))
                }
                self.contentValue = .parts(parts)
            }
        }

        // MARK: - Encodable

        private enum CodingKeys: String, CodingKey {
            case role, content
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(role, forKey: .role)

            switch contentValue {
            case .text(let str):
                try container.encode(str, forKey: .content)
            case .parts(let parts):
                var partsContainer = container.nestedUnkeyedContainer(forKey: .content)
                for part in parts {
                    switch part {
                    case .text(let text):
                        try partsContainer.encode(TextPart(type: "text", text: text))
                    case .imageURL(let url):
                        try partsContainer.encode(ImageURLPart(
                            type: "image_url",
                            image_url: ImageURLPart.ImageURL(url: url)
                        ))
                    }
                }
            }
        }

        // MARK: - Encoding helpers

        private struct TextPart: Encodable {
            let type: String
            let text: String
        }

        private struct ImageURLPart: Encodable {
            let type: String
            let image_url: ImageURL

            struct ImageURL: Encodable {
                let url: String
            }
        }
    }

    public let messages: [Message]
    public let stream: Bool?

    public init(messages: [Message], stream: Bool? = nil) {
        self.messages = messages
        self.stream = stream
    }
}
