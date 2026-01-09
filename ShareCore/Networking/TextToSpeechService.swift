//
//  TextToSpeechService.swift
//  ShareCore
//
//  Created by Codex on 2025/11/04.
//

import Foundation
import CryptoKit
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

        guard (200...299).contains(httpResponse.statusCode) else {
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
            "voice": configuration.voice
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
            "voice": configuration.voice
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    // MARK: - HMAC Signature

    private func generateSignature(timestamp: String, path: String) -> String {
        let message = "\(timestamp):\(path)"
        guard let secretData = Data(hexString: TTSConfiguration.builtInCloudSecret),
              let messageData = message.data(using: .utf8) else {
            return ""
        }

        let key = SymmetricKey(data: secretData)
        let signature = HMAC<SHA256>.authenticationCode(for: messageData, using: key)
        return Data(signature).map { String(format: "%02x", $0) }.joined()
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

// MARK: - Data Hex Extensions

private extension Data {
    /// Initialize Data from a hex string
    init?(hexString: String) {
        let hex = hexString.lowercased()
        guard hex.count % 2 == 0 else { return nil }

        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex

        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }
}
