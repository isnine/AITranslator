//
//  TTSConfiguration.swift
//  ShareCore
//
//  Created by Codex on 2025/11/04.
//

import Foundation

public struct TTSConfiguration: Equatable {
    public var endpointURL: URL
    public var apiKey: String
    public var model: String
    public var voice: String

    public init(
        endpointURL: URL,
        apiKey: String,
        model: String = "gpt-4o-mini-tts",
        voice: String = "alloy"
    ) {
        self.endpointURL = endpointURL
        self.apiKey = apiKey
        self.model = model
        self.voice = voice
    }
}

public extension TTSConfiguration {
    static let `default` = TTSConfiguration(
        endpointURL: URL(
            string: "https://REDACTED_AZURE_ENDPOINT/openai/deployments/gpt-4o-mini-tts/audio/speech?api-version=2025-03-01-preview"
        )!,
        apiKey: "REDACTED_AZURE_API_KEY",
        model: "gpt-4o-mini-tts",
        voice: "alloy"
    )
}
