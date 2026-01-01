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
        model: String,
        voice: String
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
        model: "",
        voice: ""
    )
    
    /// Whether the configuration is valid for making TTS requests
    public var isValid: Bool {
        !apiKey.isEmpty && endpointURL.absoluteString != "https://" && !model.isEmpty && !voice.isEmpty
    }
}
