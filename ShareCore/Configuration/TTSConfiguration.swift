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

    /// Empty configuration with no endpoint or API key
    public static let empty = TTSConfiguration(
        endpointURL: URL(string: "https://")!,
        apiKey: "",
        model: "gpt-4o-mini-tts",
        voice: "alloy"
    )
}
