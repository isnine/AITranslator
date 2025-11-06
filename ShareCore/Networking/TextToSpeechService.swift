//
//  TextToSpeechService.swift
//  ShareCore
//
//  Created by Codex on 2025/11/04.
//

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

        let configuration = preferences.effectiveTTSConfiguration
        var request = URLRequest(url: configuration.endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": configuration.model,
            "input": trimmed,
            "voice": configuration.voice
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TextToSpeechServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            throw TextToSpeechServiceError.httpError(
                statusCode: httpResponse.statusCode,
                body: errorBody
            )
        }

        try await playAudio(with: data)
    }

    @MainActor
    private func playAudio(with data: Data) throws {
        #if canImport(AVFoundation)
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
            return NSLocalizedString("Speech playback is not supported on this platform.", comment: "TTS platform unsupported error")
        }
    }
}
