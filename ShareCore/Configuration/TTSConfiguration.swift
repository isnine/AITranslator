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
    public var useBuiltInCloud: Bool

    public init(
        endpointURL: URL,
        apiKey: String,
        model: String,
        voice: String,
        useBuiltInCloud: Bool = false
    ) {
        self.endpointURL = endpointURL
        self.apiKey = apiKey
        self.model = model
        self.voice = voice
        self.useBuiltInCloud = useBuiltInCloud
    }

    // MARK: - Built-in Cloud Constants

    /// Built-in cloud TTS endpoint (uses CloudServiceConstants for consistency with LLM)
    public static var builtInCloudEndpoint: URL {
        CloudServiceConstants.endpoint.appendingPathComponent("tts")
    }

    /// Available voices for built-in cloud TTS
    public static let builtInCloudVoices = ["alloy", "ash", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer"]

    /// Default voice for built-in cloud TTS
    public static let builtInCloudDefaultVoice = "alloy"

    /// Built-in cloud TTS model
    public static let builtInCloudModel = "gpt-4o-mini-tts"

    /// Create a built-in cloud TTS configuration
    public static func builtInCloud(voice: String = builtInCloudDefaultVoice) -> TTSConfiguration {
        TTSConfiguration(
            endpointURL: builtInCloudEndpoint,
            apiKey: "", // Not needed for built-in cloud
            model: builtInCloudModel,
            voice: voice,
            useBuiltInCloud: true
        )
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
        if useBuiltInCloud {
            return !voice.isEmpty
        }
        return !apiKey.isEmpty && endpointURL.absoluteString != "https://" && !model.isEmpty && !voice.isEmpty
    }
}
