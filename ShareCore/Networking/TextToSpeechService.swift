//
//  TextToSpeechService.swift
//  ShareCore
//
//  Created by Codex on 2025/11/04.
//

import CryptoKit
import Foundation
#if canImport(AVFoundation)
    import AVFoundation
#endif

public final class TextToSpeechService {
    public static let shared = TextToSpeechService()

    private let urlSession: URLSession
    private let preferences: AppPreferences
    #if canImport(AVFoundation)
        private var audioPlayer: AVAudioPlayer?
    #endif

    public init(
        urlSession: URLSession = .shared,
        preferences: AppPreferences = .shared
    ) {
        self.urlSession = urlSession
        self.preferences = preferences
    }

    public func speak(text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TextToSpeechServiceError.emptyInput
        }

        let configuration = preferences.ttsConfiguration

        var request: URLRequest
        if configuration.useBuiltInCloud {
            request = try buildBuiltInCloudRequest(text: trimmed, configuration: configuration)
        } else {
            request = buildCustomRequest(text: trimmed, configuration: configuration)
        }

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TextToSpeechServiceError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            throw TextToSpeechServiceError.httpError(
                statusCode: httpResponse.statusCode,
                body: errorBody
            )
        }

        try await playAudio(with: data)
    }

    // MARK: - Request Building

    private func buildBuiltInCloudRequest(text: String, configuration: TTSConfiguration) throws -> URLRequest {
        // Validate cloud secret is configured
        guard BuildEnvironment.isCloudConfigured else {
            assertionFailure("""
                [TTS] Cloud secret not configured!
                
                To fix this, add BuiltInCloudSecret to one of these locations:
                1. Environment variable: AITRANSLATOR_CLOUD_SECRET
                2. Info.plist key: AITranslatorCloudSecret
                3. Secrets.plist file with key: BuiltInCloudSecret
                
                See README.md for detailed setup instructions.
                """)
            throw TextToSpeechServiceError.missingCloudSecret
        }

        var request = URLRequest(url: TTSConfiguration.builtInCloudEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60

        // Add HMAC signature
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let path = "/tts"
        let signature = generateSignature(timestamp: timestamp, path: path)

        request.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")
        request.setValue(signature, forHTTPHeaderField: "X-Signature")

        let body: [String: Any] = [
            "model": TTSConfiguration.builtInCloudModel,
            "input": text,
            "voice": configuration.voice,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    private func buildCustomRequest(text: String, configuration: TTSConfiguration) -> URLRequest {
        var request = URLRequest(url: configuration.endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": configuration.model,
            "input": text,
            "voice": configuration.voice,
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    // MARK: - HMAC Signature

    private func generateSignature(timestamp: String, path: String) -> String {
        let message = "\(timestamp):\(path)"
        // Use the same secret source as LLM service (from BuildEnvironment)
        let key = SymmetricKey(data: Data(hexString: CloudServiceConstants.secret) ?? Data())
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return Data(signature).hexEncodedString()
    }

    @MainActor
    private func playAudio(with data: Data) throws {
        #if canImport(AVFoundation)
            #if os(iOS)
                // Configure audio session to play even when the device is in silent mode
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
            #endif
            audioPlayer?.stop()
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        #else
            throw TextToSpeechServiceError.platformUnsupported
        #endif
    }
}

public enum TextToSpeechServiceError: LocalizedError {
    case emptyInput
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case platformUnsupported
    case missingCloudSecret

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return NSLocalizedString("No text available for speech.", comment: "TTS empty input error")
        case .invalidResponse:
            return NSLocalizedString("Unable to connect to the speech service.", comment: "TTS invalid response error")
        case let .httpError(statusCode, body):
            return String(
                format: NSLocalizedString(
                    "Speech service returned an error (%d). Details: %@",
                    comment: "TTS HTTP error"
                ),
                statusCode,
                body
            )
        case .platformUnsupported:
            return NSLocalizedString(
                "Speech playback is not supported on this platform.",
                comment: "TTS platform unsupported error"
            )
        case .missingCloudSecret:
            return NSLocalizedString(
                "Built-in TTS service is not configured. Please add BuiltInCloudSecret to Secrets.plist or set AITRANSLATOR_CLOUD_SECRET environment variable.",
                comment: "TTS missing cloud secret error"
            )
        }
    }
}
